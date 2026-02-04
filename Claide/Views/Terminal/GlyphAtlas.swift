// ABOUTME: Rasterizes glyphs to an MTLTexture using Core Text, with shelf-packing layout.
// ABOUTME: Caches glyph positions for fast lookup during rendering.

import AppKit
import Metal
import CoreText

/// Identifies a glyph variant in the atlas cache.
struct GlyphKey: Hashable {
    let codepoint: UInt32
    let bold: Bool
    let italic: Bool
}

/// Position and size of a glyph within the atlas texture.
struct GlyphEntry {
    let u0: Float
    let v0: Float
    let u1: Float
    let v1: Float
    /// Glyph dimensions in points (for quad sizing in the viewport).
    let width: Int
    let height: Int
    /// Offset from cell top-left to glyph origin, in points.
    let bearingX: Float
    let bearingY: Float
}

/// Shelf-packed glyph atlas backed by an MTLTexture.
///
/// Rasterizes glyphs lazily using Core Text. Each glyph is drawn into a small
/// bitmap, then uploaded to the atlas at the next available position.
/// Shelves are horizontal rows of uniform height.
final class GlyphAtlas {
    let device: MTLDevice
    private(set) var texture: MTLTexture
    private var cache: [GlyphKey: GlyphEntry] = [:]

    private var shelfY: Int = 0       // Y position of current shelf
    private var shelfHeight: Int = 0  // Height of current shelf
    private var cursorX: Int = 0      // X position within current shelf
    private let atlasWidth: Int
    private let atlasHeight: Int
    private let padding: Int = 1      // Pixels between glyphs

    private var regularFont: CTFont
    private var boldFont: CTFont
    private var italicFont: CTFont
    private var boldItalicFont: CTFont

    /// Backing scale factor for Retina rasterization.
    private(set) var scale: CGFloat

    /// Cell dimensions determined by the font metrics (in points).
    private(set) var cellWidth: CGFloat = 0
    private(set) var cellHeight: CGFloat = 0
    private(set) var descent: CGFloat = 0

    init(device: MTLDevice, font: NSFont, scale: CGFloat = 2.0, width: Int = 2048, height: Int = 2048) {
        self.device = device
        self.scale = scale
        self.atlasWidth = width
        self.atlasHeight = height

        // Create font variants
        let size = font.pointSize
        let baseFont = CTFontCreateWithName(font.fontName as CFString, size, nil)
        self.regularFont = baseFont

        if let bold = CTFontCreateCopyWithSymbolicTraits(baseFont, size, nil, .boldTrait, .boldTrait) {
            self.boldFont = bold
        } else {
            self.boldFont = baseFont
        }

        if let italic = CTFontCreateCopyWithSymbolicTraits(baseFont, size, nil, .italicTrait, .italicTrait) {
            self.italicFont = italic
        } else {
            self.italicFont = baseFont
        }

        if let bi = CTFontCreateCopyWithSymbolicTraits(baseFont, size, nil, [.boldTrait, .italicTrait], [.boldTrait, .italicTrait]) {
            self.boldItalicFont = bi
        } else {
            self.boldItalicFont = self.boldFont
        }

        // Calculate cell dimensions from the regular font
        let ascent = CTFontGetAscent(baseFont)
        let desc = CTFontGetDescent(baseFont)
        let leading = CTFontGetLeading(baseFont)
        self.descent = desc
        self.cellHeight = ceil(ascent + desc + leading)

        // Use the advance width of 'M' for cell width
        var glyph = CTFontGetGlyphWithName(baseFont, "M" as CFString)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(baseFont, .horizontal, &glyph, &advance, 1)
        self.cellWidth = ceil(advance.width)

        // Create the atlas texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        self.texture = device.makeTexture(descriptor: descriptor)!
    }

    /// Look up or rasterize a glyph, returning its atlas entry.
    func entry(for codepoint: UInt32, bold: Bool, italic: Bool) -> GlyphEntry? {
        let key = GlyphKey(codepoint: codepoint, bold: bold, italic: italic)
        if let existing = cache[key] {
            return existing
        }

        guard let scalar = Unicode.Scalar(codepoint) else { return nil }
        let char = Character(scalar)
        let string = String(char)

        // Skip spaces and control characters
        if codepoint <= 0x20 || codepoint == 0x7F {
            return nil
        }

        // Pick the right font variant
        let font: CTFont
        switch (bold, italic) {
        case (true, true): font = boldItalicFont
        case (true, false): font = boldFont
        case (false, true): font = italicFont
        case (false, false): font = regularFont
        }

        // Create attributed string and line
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let attrStr = NSAttributedString(string: string, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])

        // Glyph dimensions in points (for quad sizing)
        let glyphWidth = max(Int(ceil(bounds.width)) + 2, 1)
        let glyphHeight = max(Int(ceil(bounds.height)) + 2, 1)

        // Bitmap at native pixel resolution for Retina clarity
        let bitmapWidth = Int(ceil(CGFloat(glyphWidth) * scale))
        let bitmapHeight = Int(ceil(CGFloat(glyphHeight) * scale))

        // Shelf packing in pixel dimensions
        if cursorX + bitmapWidth + padding > atlasWidth {
            shelfY += shelfHeight + padding
            shelfHeight = 0
            cursorX = 0
        }

        if shelfY + bitmapHeight > atlasHeight {
            return nil
        }

        shelfHeight = max(shelfHeight, bitmapHeight)

        // Rasterize at native resolution
        var pixels = [UInt8](repeating: 0, count: bitmapWidth * bitmapHeight)

        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: bitmapWidth,
                height: bitmapHeight,
                bitsPerComponent: 8,
                bytesPerRow: bitmapWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }

            // Scale so Core Text renders at native pixel density
            context.scaleBy(x: scale, y: scale)

            context.setAllowsFontSmoothing(true)
            context.setShouldSmoothFonts(true)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            // Draw at the glyph's natural position (in points, scaled by context)
            let drawX = -bounds.origin.x + 1
            let drawY = -bounds.origin.y + 1
            context.textPosition = CGPoint(x: drawX, y: drawY)
            CTLineDraw(line, context)
        }

        // Upload to atlas (pixel dimensions)
        let region = MTLRegion(
            origin: MTLOrigin(x: cursorX, y: shelfY, z: 0),
            size: MTLSize(width: bitmapWidth, height: bitmapHeight, depth: 1)
        )
        texture.replace(region: region, mipmapLevel: 0, withBytes: &pixels, bytesPerRow: bitmapWidth)

        // UV coordinates reference the pixel-sized region in the atlas.
        // Width/height stay in points for quad sizing in the viewport.
        let fw = Float(atlasWidth)
        let fh = Float(atlasHeight)
        let entry = GlyphEntry(
            u0: Float(cursorX) / fw,
            v0: Float(shelfY) / fh,
            u1: Float(cursorX + bitmapWidth) / fw,
            v1: Float(shelfY + bitmapHeight) / fh,
            width: glyphWidth,
            height: glyphHeight,
            bearingX: Float(bounds.origin.x) - 1,
            bearingY: Float(bounds.origin.y) - 1
        )

        cache[key] = entry
        cursorX += bitmapWidth + padding

        return entry
    }

    /// Update the backing scale factor, clearing the atlas cache.
    func setScale(_ newScale: CGFloat) {
        guard newScale != scale else { return }
        scale = newScale
        clearAtlas()
    }

    /// Update the font, clearing the atlas cache.
    func setFont(_ font: NSFont) {
        let size = font.pointSize
        let baseFont = CTFontCreateWithName(font.fontName as CFString, size, nil)
        regularFont = baseFont

        if let bold = CTFontCreateCopyWithSymbolicTraits(baseFont, size, nil, .boldTrait, .boldTrait) {
            boldFont = bold
        } else {
            boldFont = baseFont
        }

        if let italic = CTFontCreateCopyWithSymbolicTraits(baseFont, size, nil, .italicTrait, .italicTrait) {
            italicFont = italic
        } else {
            italicFont = baseFont
        }

        if let bi = CTFontCreateCopyWithSymbolicTraits(baseFont, size, nil, [.boldTrait, .italicTrait], [.boldTrait, .italicTrait]) {
            boldItalicFont = bi
        } else {
            boldItalicFont = boldFont
        }

        let ascent = CTFontGetAscent(baseFont)
        let desc = CTFontGetDescent(baseFont)
        let leading = CTFontGetLeading(baseFont)
        descent = desc
        cellHeight = ceil(ascent + desc + leading)

        var glyph = CTFontGetGlyphWithName(baseFont, "M" as CFString)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(baseFont, .horizontal, &glyph, &advance, 1)
        cellWidth = ceil(advance.width)

        clearAtlas()
    }

    private func clearAtlas() {
        cache.removeAll()
        shelfY = 0
        shelfHeight = 0
        cursorX = 0

        let zeros = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)
        let region = MTLRegion(origin: MTLOrigin(), size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1))
        texture.replace(region: region, mipmapLevel: 0, withBytes: zeros, bytesPerRow: atlasWidth)
    }
}
