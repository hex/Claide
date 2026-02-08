// ABOUTME: Builds Metal instance buffers from terminal grid snapshots.
// ABOUTME: Produces background, text, and emoji draw calls for the terminal content.

import Metal

/// Matches the CellInstance struct in TerminalShaders.metal.
struct CellInstance {
    var position: SIMD2<Float>     // top-left in pixels
    var size: SIMD2<Float>         // cell size in pixels
    var color: SIMD4<Float>        // RGBA
    var texCoords: SIMD4<Float>    // (u0, v0, u1, v1)
}

/// Matches the Uniforms struct in TerminalShaders.metal.
struct Uniforms {
    var viewportSize: SIMD2<Float>
}

/// Converts a grid snapshot into Metal instance buffers for rendering.
final class GridRenderer {
    let device: MTLDevice
    let atlas: GlyphAtlas

    // Pipeline states
    private let backgroundPipeline: MTLRenderPipelineState
    private let glyphPipeline: MTLRenderPipelineState
    private let emojiPipeline: MTLRenderPipelineState

    // Instance buffers — pre-allocated and grown as needed to avoid per-frame allocation
    private var backgroundBuffer: MTLBuffer?
    private var glyphBuffer: MTLBuffer?
    private var emojiBuffer: MTLBuffer?
    private var backgroundBufferCapacity: Int = 0
    private var glyphBufferCapacity: Int = 0
    private var emojiBufferCapacity: Int = 0
    private var backgroundCount: Int = 0
    private var glyphCount: Int = 0
    private var emojiCount: Int = 0

    /// Terminal background color (used for Metal clear color).
    var defaultBg: SIMD3<Float> = SIMD3<Float>(
        Float(0x15) / 255.0,
        Float(0x17) / 255.0,
        Float(0x28) / 255.0
    )

    /// Selection highlight background color.
    var selectionBg: SIMD3<Float> = SIMD3<Float>(
        Float(131) / 255.0,
        Float(74) / 255.0,
        Float(136) / 255.0
    )

    /// Search match highlight background color (yellow-orange).
    var searchMatchBg: SIMD3<Float> = SIMD3<Float>(0.8, 0.6, 0.1)

    /// Cursor color (RGB, alpha applied per shape).
    var cursorColor: SIMD3<Float> = SIMD3<Float>(0.92, 0.92, 0.92)

    /// Apply a color scheme to the renderer's configurable colors.
    func applyScheme(_ scheme: TerminalColorScheme) {
        defaultBg = SIMD3<Float>(
            Float(scheme.background.r) / 255.0,
            Float(scheme.background.g) / 255.0,
            Float(scheme.background.b) / 255.0
        )
        selectionBg = SIMD3<Float>(
            Float(scheme.selection.r) / 255.0,
            Float(scheme.selection.g) / 255.0,
            Float(scheme.selection.b) / 255.0
        )
        cursorColor = SIMD3<Float>(
            Float(scheme.cursor.r) / 255.0,
            Float(scheme.cursor.g) / 255.0,
            Float(scheme.cursor.b) / 255.0
        )
    }

    init(device: MTLDevice, atlas: GlyphAtlas, library: MTLLibrary) throws {
        self.device = device
        self.atlas = atlas

        let vertexFn = library.makeFunction(name: "cellVertex")!
        let bgFragFn = library.makeFunction(name: "backgroundFragment")!
        let glyphFragFn = library.makeFunction(name: "glyphFragment")!
        let emojiFragFn = library.makeFunction(name: "emojiFragment")!

        // Background pipeline (opaque)
        let bgDesc = MTLRenderPipelineDescriptor()
        bgDesc.vertexFunction = vertexFn
        bgDesc.fragmentFunction = bgFragFn
        bgDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        backgroundPipeline = try device.makeRenderPipelineState(descriptor: bgDesc)

        // Glyph pipeline (premultiplied alpha blending for subpixel text)
        let glyphDesc = MTLRenderPipelineDescriptor()
        glyphDesc.vertexFunction = vertexFn
        glyphDesc.fragmentFunction = glyphFragFn
        glyphDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        glyphDesc.colorAttachments[0].isBlendingEnabled = true
        glyphDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        glyphDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        glyphDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        glyphDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        glyphPipeline = try device.makeRenderPipelineState(descriptor: glyphDesc)

        // Emoji pipeline (premultiplied alpha blending for RGBA color emoji)
        let emojiDesc = MTLRenderPipelineDescriptor()
        emojiDesc.vertexFunction = vertexFn
        emojiDesc.fragmentFunction = emojiFragFn
        emojiDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        emojiDesc.colorAttachments[0].isBlendingEnabled = true
        emojiDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        emojiDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        emojiDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        emojiDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        emojiPipeline = try device.makeRenderPipelineState(descriptor: emojiDesc)
    }

    /// Build instance buffers from a sparse grid snapshot.
    /// When `yOffset` is non-zero, the grid is shifted up so the bottom rows
    /// remain visible (used for visual-only font zoom).
    func update(snapshot: UnsafePointer<ClaideGridSnapshot>, yOffset: Float = 0, origin: SIMD2<Float> = .zero) {
        let cellCount = Int(snapshot.pointee.cell_count)
        let cellW = Float(atlas.cellWidth)
        let cellH = Float(atlas.cellHeight)

        var bgInstances: [CellInstance] = []
        var glyphInstances: [CellInstance] = []
        var emojiInstances: [CellInstance] = []

        bgInstances.reserveCapacity(cellCount)
        glyphInstances.reserveCapacity(cellCount)

        // Convert defaultBg to UInt8 for fast comparison against cell bg bytes
        let defBgR = UInt8(round(defaultBg.x * 255.0))
        let defBgG = UInt8(round(defaultBg.y * 255.0))
        let defBgB = UInt8(round(defaultBg.z * 255.0))

        let cells = snapshot.pointee.cells!
        let extraChars = snapshot.pointee.extra_chars
        let scale = Float(atlas.scale)
        let descent = Float(atlas.descent)

        for i in 0..<cellCount {
            let cell = cells[i]

            let x = Float(cell.col) * cellW + origin.x
            let y = Float(cell.row) * cellH - yOffset + origin.y

            let selected = cell.flags & 0x200 != 0
            let searchMatch = cell.flags & 0x400 != 0

            let fgR = Float(cell.fg_r) / 255.0
            let fgG = Float(cell.fg_g) / 255.0
            let fgB = Float(cell.fg_b) / 255.0

            // Search match > selection > normal background
            let bgR: Float
            let bgG: Float
            let bgB: Float

            if searchMatch {
                bgR = searchMatchBg.x
                bgG = searchMatchBg.y
                bgB = searchMatchBg.z
            } else if selected {
                bgR = selectionBg.x
                bgG = selectionBg.y
                bgB = selectionBg.z
            } else {
                bgR = Float(cell.bg_r) / 255.0
                bgG = Float(cell.bg_g) / 255.0
                bgB = Float(cell.bg_b) / 255.0
            }

            // Skip background quads that match the clear color (already filled by Metal)
            let isDefaultBg = !selected && !searchMatch
                && cell.bg_r == defBgR && cell.bg_g == defBgG && cell.bg_b == defBgB
            if !isDefaultBg {
                bgInstances.append(CellInstance(
                    position: SIMD2(x, y),
                    size: SIMD2(cellW, cellH),
                    color: SIMD4(bgR, bgG, bgB, 1.0),
                    texCoords: SIMD4(0, 0, 0, 0)
                ))
            }

            // Skip wide char spacers
            if cell.flags & 0x80 != 0 { continue }

            // Skip spaces and control chars
            let cp = cell.codepoint
            if cp <= 0x20 || cp == 0x7F { continue }

            let bold = cell.flags & 0x01 != 0
            let italic = cell.flags & 0x02 != 0

            // Multi-codepoint cell: build full string for emoji lookup
            let glyph: GlyphEntry?
            if cell.extra_count > 0, let extras = extraChars {
                var string = ""
                if let scalar = Unicode.Scalar(cp) {
                    string.append(Character(scalar))
                }
                for j in 0..<Int(cell.extra_count) {
                    let extraCP = extras[Int(cell.extra_offset) + j]
                    if let scalar = Unicode.Scalar(extraCP) {
                        string.append(Character(scalar))
                    }
                }
                glyph = atlas.emojiEntry(for: string)
            } else {
                glyph = atlas.entry(for: cp, bold: bold, italic: italic)
            }

            guard let glyph else { continue }

            // Snap glyph position to pixel boundaries for sharp text at all scales
            let glyphX = ((x + glyph.bearingX) * scale).rounded() / scale
            let rawY = y + cellH - descent - Float(glyph.height) - glyph.bearingY
            let glyphY = (rawY * scale).rounded() / scale

            let instance = CellInstance(
                position: SIMD2(glyphX, glyphY),
                size: SIMD2(Float(glyph.width), Float(glyph.height)),
                color: SIMD4(fgR, fgG, fgB, 1.0),
                texCoords: SIMD4(glyph.u0, glyph.v0, glyph.u1, glyph.v1)
            )

            if glyph.isEmoji {
                emojiInstances.append(instance)
            } else {
                glyphInstances.append(instance)
            }
        }

        // Cursor overlay
        let cursor = snapshot.pointee.cursor
        let rows = Int(snapshot.pointee.rows)
        let cols = Int(snapshot.pointee.cols)
        if cursor.visible && cursor.row < rows && cursor.col < cols {
            let cx = Float(cursor.col) * cellW + origin.x
            let cy = Float(cursor.row) * cellH - yOffset + origin.y

            let cc = cursorColor
            switch cursor.shape {
            case 0, 4: // Block or HollowBlock
                let alpha: Float = cursor.shape == 0 ? 0.6 : 0.3
                bgInstances.append(CellInstance(
                    position: SIMD2(cx, cy),
                    size: SIMD2(cellW, cellH),
                    color: SIMD4(cc.x, cc.y, cc.z, alpha),
                    texCoords: SIMD4(0, 0, 0, 0)
                ))
            case 1: // Underline
                bgInstances.append(CellInstance(
                    position: SIMD2(cx, cy + cellH - 2),
                    size: SIMD2(cellW, 2),
                    color: SIMD4(cc.x, cc.y, cc.z, 0.9),
                    texCoords: SIMD4(0, 0, 0, 0)
                ))
            case 2: // Beam
                bgInstances.append(CellInstance(
                    position: SIMD2(cx, cy),
                    size: SIMD2(2, cellH),
                    color: SIMD4(cc.x, cc.y, cc.z, 0.9),
                    texCoords: SIMD4(0, 0, 0, 0)
                ))
            default:
                break
            }
        }

        backgroundCount = bgInstances.count
        glyphCount = glyphInstances.count
        emojiCount = emojiInstances.count

        backgroundBuffer = ensureBuffer(backgroundBuffer, capacity: &backgroundBufferCapacity, data: bgInstances)
        glyphBuffer = ensureBuffer(glyphBuffer, capacity: &glyphBufferCapacity, data: glyphInstances)
        emojiBuffer = ensureBuffer(emojiBuffer, capacity: &emojiBufferCapacity, data: emojiInstances)
    }

    /// Encode draw calls into a render command encoder.
    func draw(encoder: MTLRenderCommandEncoder, viewportSize: SIMD2<Float>) {
        var uniforms = Uniforms(viewportSize: viewportSize)

        // Background pass
        if let bgBuf = backgroundBuffer, backgroundCount > 0 {
            encoder.setRenderPipelineState(backgroundPipeline)
            encoder.setVertexBuffer(bgBuf, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: backgroundCount)
        }

        // Glyph pass (text atlas, R8)
        if let glyphBuf = glyphBuffer, glyphCount > 0 {
            encoder.setRenderPipelineState(glyphPipeline)
            encoder.setVertexBuffer(glyphBuf, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(atlas.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: glyphCount)
        }

        // Emoji pass (emoji atlas, RGBA8)
        if let emojiBuf = emojiBuffer, emojiCount > 0 {
            encoder.setRenderPipelineState(emojiPipeline)
            encoder.setVertexBuffer(emojiBuf, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(atlas.emojiTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: emojiCount)
        }
    }

    /// Reuse an existing Metal buffer if it has enough capacity, otherwise allocate a new one.
    /// Copies instance data into the buffer via memcpy (avoids per-frame GPU allocation).
    private func ensureBuffer(_ existing: MTLBuffer?, capacity: inout Int, data: [CellInstance]) -> MTLBuffer? {
        guard !data.isEmpty else { return existing }
        let needed = data.count * MemoryLayout<CellInstance>.stride
        var buffer = existing
        if buffer == nil || capacity < needed {
            let allocSize = max(needed, 4096)
            buffer = device.makeBuffer(length: allocSize, options: .storageModeShared)
            capacity = allocSize
        }
        if let buf = buffer {
            data.withUnsafeBytes { src in
                buf.contents().copyMemory(from: src.baseAddress!, byteCount: needed)
            }
        }
        return buffer
    }
}
