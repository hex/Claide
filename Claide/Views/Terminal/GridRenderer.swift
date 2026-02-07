// ABOUTME: Builds Metal instance buffers from terminal grid snapshots.
// ABOUTME: Produces background and foreground draw calls for the terminal content.

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

    // Instance buffers (double-buffered for frame overlap)
    private var backgroundBuffer: MTLBuffer?
    private var glyphBuffer: MTLBuffer?
    private var backgroundCount: Int = 0
    private var glyphCount: Int = 0

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

        // Background pipeline (opaque)
        let bgDesc = MTLRenderPipelineDescriptor()
        bgDesc.vertexFunction = vertexFn
        bgDesc.fragmentFunction = bgFragFn
        bgDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        backgroundPipeline = try device.makeRenderPipelineState(descriptor: bgDesc)

        // Glyph pipeline (premultiplied alpha blending)
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
    }

    /// Build instance buffers from a grid snapshot.
    /// When `yOffset` is non-zero, the grid is shifted up so the bottom rows
    /// remain visible (used for visual-only font zoom).
    func update(snapshot: UnsafePointer<ClaideGridSnapshot>, yOffset: Float = 0, origin: SIMD2<Float> = .zero) {
        let rows = Int(snapshot.pointee.rows)
        let cols = Int(snapshot.pointee.cols)
        let cellW = Float(atlas.cellWidth)
        let cellH = Float(atlas.cellHeight)

        var bgInstances: [CellInstance] = []
        var glyphInstances: [CellInstance] = []

        bgInstances.reserveCapacity(rows * cols)
        glyphInstances.reserveCapacity(rows * cols)

        let cells = snapshot.pointee.cells!

        for row in 0..<rows {
            for col in 0..<cols {
                let idx = row * cols + col
                let cell = cells[idx]

                let x = Float(col) * cellW + origin.x
                let y = Float(row) * cellH - yOffset + origin.y

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

                // Background quad
                bgInstances.append(CellInstance(
                    position: SIMD2(x, y),
                    size: SIMD2(cellW, cellH),
                    color: SIMD4(bgR, bgG, bgB, 1.0),
                    texCoords: SIMD4(0, 0, 0, 0)
                ))

                // Skip wide char spacers
                if cell.flags & 0x80 != 0 { continue }

                // Skip spaces and control chars
                let cp = cell.codepoint
                if cp <= 0x20 || cp == 0x7F { continue }

                let bold = cell.flags & 0x01 != 0
                let italic = cell.flags & 0x02 != 0

                guard let glyph = atlas.entry(for: cp, bold: bold, italic: italic) else { continue }

                // Snap glyph position to pixel boundaries for sharp text at all scales
                let scale = Float(atlas.scale)
                let glyphX = ((x + glyph.bearingX) * scale).rounded() / scale
                let rawY = y + cellH - Float(atlas.descent) - Float(glyph.height) - glyph.bearingY
                let glyphY = (rawY * scale).rounded() / scale

                glyphInstances.append(CellInstance(
                    position: SIMD2(glyphX, glyphY),
                    size: SIMD2(Float(glyph.width), Float(glyph.height)),
                    color: SIMD4(fgR, fgG, fgB, 1.0),
                    texCoords: SIMD4(glyph.u0, glyph.v0, glyph.u1, glyph.v1)
                ))
            }
        }

        // Cursor overlay
        let cursor = snapshot.pointee.cursor
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

        if !bgInstances.isEmpty {
            let size = bgInstances.count * MemoryLayout<CellInstance>.stride
            backgroundBuffer = device.makeBuffer(bytes: &bgInstances, length: size, options: .storageModeShared)
        }

        if !glyphInstances.isEmpty {
            let size = glyphInstances.count * MemoryLayout<CellInstance>.stride
            glyphBuffer = device.makeBuffer(bytes: &glyphInstances, length: size, options: .storageModeShared)
        }
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

        // Glyph pass
        if let glyphBuf = glyphBuffer, glyphCount > 0 {
            encoder.setRenderPipelineState(glyphPipeline)
            encoder.setVertexBuffer(glyphBuf, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(atlas.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: glyphCount)
        }
    }
}
