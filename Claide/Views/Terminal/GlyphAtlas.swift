// ABOUTME: Rasterizes glyphs to MTLTextures using Core Text, with shelf-packing layout.
// ABOUTME: Uses dual atlas: R8 for text (subpixel coverage), RGBA8 for color emoji.

import AppKit
import Metal
import CoreText

/// Identifies a glyph variant in the text atlas cache.
struct GlyphKey: Hashable {
    let codepoint: UInt32
    let bold: Bool
    let italic: Bool
}

/// Position and size of a glyph within an atlas texture.
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
    /// Which atlas this glyph lives in (text R8 vs emoji RGBA8).
    let isEmoji: Bool
}

/// Shelf-packed glyph atlas backed by two MTLTextures.
///
/// Text glyphs are rasterized to a single-channel R8 texture (subpixel coverage).
/// Color emoji are rasterized to a separate RGBA8 texture (full color).
/// Both use independent shelf-packing for layout.
final class GlyphAtlas {
    let device: MTLDevice

    /// Text atlas: single-channel grayscale coverage (R8).
    private(set) var texture: MTLTexture
    /// Emoji atlas: full-color RGBA for color glyphs.
    private(set) var emojiTexture: MTLTexture

    private var cache: [GlyphKey: GlyphEntry] = [:]
    private var emojiCache: [String: GlyphEntry] = [:]

    // Text atlas shelf-packing state
    private var shelfY: Int = 0
    private var shelfHeight: Int = 0
    private var cursorX: Int = 0

    // Emoji atlas shelf-packing state
    private var emojiShelfY: Int = 0
    private var emojiShelfHeight: Int = 0
    private var emojiCursorX: Int = 0

    private let atlasWidth: Int
    private let atlasHeight: Int
    private let padding: Int = 1

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

        // Text atlas (single-channel grayscale coverage)
        let textDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textDesc.usage = [.shaderRead]
        textDesc.storageMode = .managed
        self.texture = device.makeTexture(descriptor: textDesc)!

        // Emoji atlas (RGBA for color glyphs)
        let emojiDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        emojiDesc.usage = [.shaderRead]
        emojiDesc.storageMode = .managed
        self.emojiTexture = device.makeTexture(descriptor: emojiDesc)!
    }

    /// Check if a string resolves to a color emoji font via Core Text fallback.
    private func isColorEmoji(_ string: String) -> Bool {
        let cfString = string as CFString
        let range = CFRangeMake(0, CFStringGetLength(cfString))
        let resolvedFont = CTFontCreateForString(regularFont, cfString, range)
        return CTFontGetSymbolicTraits(resolvedFont).contains(.traitColorGlyphs)
    }

    /// Look up or rasterize a glyph, returning its atlas entry.
    /// Automatically detects color emoji and routes to the RGBA atlas.
    func entry(for codepoint: UInt32, bold: Bool, italic: Bool) -> GlyphEntry? {
        let key = GlyphKey(codepoint: codepoint, bold: bold, italic: italic)
        if let existing = cache[key] {
            return existing
        }

        guard let scalar = Unicode.Scalar(codepoint) else { return nil }
        let string = String(Character(scalar))

        // Skip spaces and control characters
        if codepoint <= 0x20 || codepoint == 0x7F {
            return nil
        }

        // Route color emoji to the RGBA atlas
        if isColorEmoji(string) {
            if let entry = rasterizeEmoji(string) {
                cache[key] = entry
                return entry
            }
            return nil
        }

        // Pick the right font variant for text
        let font: CTFont
        switch (bold, italic) {
        case (true, true): font = boldItalicFont
        case (true, false): font = boldFont
        case (false, true): font = italicFont
        case (false, false): font = regularFont
        }

        return rasterizeText(string, font: font, key: key)
    }

    /// Look up or rasterize a multi-codepoint emoji (ZWJ sequences, skin tones).
    func emojiEntry(for string: String) -> GlyphEntry? {
        if let existing = emojiCache[string] {
            return existing
        }
        return rasterizeEmoji(string)
    }

    // MARK: - Text rasterization (R8 atlas)

    private func rasterizeText(_ string: String, font: CTFont, key: GlyphKey) -> GlyphEntry? {
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

        // Rasterize in sRGB BGRA (preserves Core Text's full rendering quality),
        // then extract the R channel for the single-channel atlas.
        let bgraBytes = 4
        var bgraPixels = [UInt8](repeating: 0, count: bitmapWidth * bitmapHeight * bgraBytes)

        bgraPixels.withUnsafeMutableBufferPointer { buffer in
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: bitmapWidth,
                height: bitmapHeight,
                bitsPerComponent: 8,
                bytesPerRow: bitmapWidth * bgraBytes,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: bitmapInfo
            ) else { return }

            // Fill with opaque black (font smoothing needs a solid background)
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: bitmapWidth, height: bitmapHeight))

            // Scale so Core Text renders at native pixel density
            context.scaleBy(x: scale, y: scale)

            context.setAllowsFontSmoothing(true)
            context.setShouldSmoothFonts(true)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            // Draw white text — RGB values are per-channel coverage (R==G==B on macOS 10.14+)
            let drawX = -bounds.origin.x + 1
            let drawY = -bounds.origin.y + 1
            context.textPosition = CGPoint(x: drawX, y: drawY)
            CTLineDraw(line, context)
        }

        // Extract R channel from BGRA (byteOrder32Little: B=0, G=1, R=2, A=3)
        var pixels = [UInt8](repeating: 0, count: bitmapWidth * bitmapHeight)
        for i in 0..<(bitmapWidth * bitmapHeight) {
            pixels[i] = bgraPixels[i * bgraBytes + 2]  // R channel
        }

        // Upload to atlas (pixel dimensions, 1 byte per pixel)
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
            bearingY: Float(bounds.origin.y) - 1,
            isEmoji: false
        )

        cache[key] = entry
        cursorX += bitmapWidth + padding

        return entry
    }

    // MARK: - Emoji rasterization (RGBA8 atlas)

    private func rasterizeEmoji(_ string: String) -> GlyphEntry? {
        if let existing = emojiCache[string] {
            return existing
        }

        // Resolve the emoji font via Core Text fallback
        let cfString = string as CFString
        let range = CFRangeMake(0, CFStringGetLength(cfString))
        let emojiFont = CTFontCreateForString(regularFont, cfString, range)

        let attrs: [NSAttributedString.Key: Any] = [.font: emojiFont]
        let attrStr = NSAttributedString(string: string, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)

        // Typographic bounds (not glyph path bounds, which return zero for bitmap emoji)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        let glyphWidth: Int
        let glyphHeight: Int
        let bearingX: Float
        let bearingY: Float

        if bounds.width > 0 && bounds.height > 0 {
            glyphWidth = max(Int(ceil(bounds.width)) + 2, 1)
            glyphHeight = max(Int(ceil(bounds.height)) + 2, 1)
            bearingX = Float(bounds.origin.x) - 1
            bearingY = Float(bounds.origin.y) - 1
        } else {
            // Degenerate bounds fallback: size to 2 cells wide, 1 cell tall
            glyphWidth = Int(cellWidth * 2)
            glyphHeight = Int(cellHeight)
            bearingX = 0
            bearingY = 0
        }

        let bitmapWidth = Int(ceil(CGFloat(glyphWidth) * scale))
        let bitmapHeight = Int(ceil(CGFloat(glyphHeight) * scale))

        // Emoji shelf packing
        if emojiCursorX + bitmapWidth + padding > atlasWidth {
            emojiShelfY += emojiShelfHeight + padding
            emojiShelfHeight = 0
            emojiCursorX = 0
        }
        if emojiShelfY + bitmapHeight > atlasHeight { return nil }
        emojiShelfHeight = max(emojiShelfHeight, bitmapHeight)

        // Rasterize in RGBA with premultiplied alpha (no opaque black fill)
        let rgbaBytes = 4
        var pixels = [UInt8](repeating: 0, count: bitmapWidth * bitmapHeight * rgbaBytes)

        pixels.withUnsafeMutableBufferPointer { buffer in
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: bitmapWidth,
                height: bitmapHeight,
                bitsPerComponent: 8,
                bytesPerRow: bitmapWidth * rgbaBytes,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: bitmapInfo
            ) else { return }

            context.scaleBy(x: scale, y: scale)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            let drawX: CGFloat
            let drawY: CGFloat
            if bounds.width > 0 && bounds.height > 0 {
                drawX = -bounds.origin.x + 1
                drawY = -bounds.origin.y + 1
            } else {
                drawX = 0
                drawY = descent
            }
            context.textPosition = CGPoint(x: drawX, y: drawY)
            CTLineDraw(line, context)
        }

        // Upload RGBA to emoji atlas (4 bytes per pixel)
        let region = MTLRegion(
            origin: MTLOrigin(x: emojiCursorX, y: emojiShelfY, z: 0),
            size: MTLSize(width: bitmapWidth, height: bitmapHeight, depth: 1)
        )
        emojiTexture.replace(region: region, mipmapLevel: 0, withBytes: &pixels, bytesPerRow: bitmapWidth * rgbaBytes)

        let fw = Float(atlasWidth)
        let fh = Float(atlasHeight)
        let entry = GlyphEntry(
            u0: Float(emojiCursorX) / fw,
            v0: Float(emojiShelfY) / fh,
            u1: Float(emojiCursorX + bitmapWidth) / fw,
            v1: Float(emojiShelfY + bitmapHeight) / fh,
            width: glyphWidth,
            height: glyphHeight,
            bearingX: bearingX,
            bearingY: bearingY,
            isEmoji: true
        )

        emojiCache[string] = entry
        emojiCursorX += bitmapWidth + padding

        return entry
    }

    // MARK: - Configuration

    /// Update the backing scale factor, clearing both atlas caches.
    func setScale(_ newScale: CGFloat) {
        guard newScale != scale else { return }
        scale = newScale
        clearAtlas()
    }

    /// Update the font, clearing both atlas caches.
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
        emojiCache.removeAll()

        shelfY = 0
        shelfHeight = 0
        cursorX = 0

        emojiShelfY = 0
        emojiShelfHeight = 0
        emojiCursorX = 0

        // Clear text atlas
        let zeros = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)
        let region = MTLRegion(origin: MTLOrigin(), size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1))
        texture.replace(region: region, mipmapLevel: 0, withBytes: zeros, bytesPerRow: atlasWidth)

        // Recreate emoji texture (avoids allocating a large zeroed buffer)
        let emojiDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        emojiDesc.usage = [.shaderRead]
        emojiDesc.storageMode = .managed
        emojiTexture = device.makeTexture(descriptor: emojiDesc)!
    }
}
