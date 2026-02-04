// ABOUTME: NSView backed by a CAMetalLayer for GPU-accelerated terminal rendering.
// ABOUTME: Handles keyboard input, display-linked rendering, and terminal lifecycle.

import AppKit
import Metal
import QuartzCore

// CVDisplayLink callback — must be file-level to avoid @MainActor isolation inheritance.
private func displayLinkFired(
    _ link: CVDisplayLink,
    _ now: UnsafePointer<CVTimeStamp>,
    _ output: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ userInfo: UnsafeMutableRawPointer?
) -> CVReturn {
    let view = Unmanaged<MetalTerminalView>.fromOpaque(userInfo!).takeUnretainedValue()
    DispatchQueue.main.async {
        view.displayLinkTick()
    }
    return kCVReturnSuccess
}

/// GPU-accelerated terminal view using Metal for rendering and alacritty_terminal for emulation.
final class MetalTerminalView: NSView, CALayerDelegate {

    // MARK: - Properties

    private var metalLayer: CAMetalLayer!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var atlas: GlyphAtlas!
    private var gridRenderer: GridRenderer!

    private var displayLink: CVDisplayLink?
    private var needsRedraw = true

    /// Terminal bridge (set when startShell is called).
    private(set) var bridge: TerminalBridge?

    /// Current font.
    var terminalFont: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) {
        didSet {
            atlas?.setFont(terminalFont)
            needsRedraw = true
            if let bridge {
                let (cols, rows) = gridDimensions
                bridge.resize(
                    cols: UInt32(cols), rows: UInt32(rows),
                    cellWidth: UInt16(atlas.cellWidth),
                    cellHeight: UInt16(atlas.cellHeight)
                )
            }
        }
    }

    /// Shell process ID (0 if no shell running).
    var shellPid: UInt32 { bridge?.shellPid ?? 0 }

    /// Computed grid dimensions from view size and cell metrics.
    var gridDimensions: (cols: Int, rows: Int) {
        guard let atlas else { return (80, 24) }
        let cols = max(2, Int(bounds.width / atlas.cellWidth))
        let rows = max(1, Int(bounds.height / atlas.cellHeight))
        return (cols, rows)
    }

    /// Whether to treat Option key as Meta (sends ESC prefix).
    var optionAsMeta = true

    // MARK: - Initialization

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not available")
        }
        device = dev
        commandQueue = dev.makeCommandQueue()!

        // Set up CAMetalLayer
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        layer = metalLayer

        // Initialize atlas and renderer
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        atlas = GlyphAtlas(device: device, font: terminalFont, scale: scale)

        let library = device.makeDefaultLibrary()!
        gridRenderer = try! GridRenderer(device: device, atlas: atlas, library: library)

        startDisplayLink()
    }

    deinit {
        stopDisplayLink()
    }

    // MARK: - Shell Lifecycle

    /// Start a shell process in the terminal.
    func startShell(
        executable: String,
        args: [String],
        environment: [(String, String)],
        directory: String
    ) {
        let (cols, rows) = gridDimensions

        bridge = TerminalBridge(
            shell: executable,
            args: args,
            environment: environment,
            directory: directory,
            cols: UInt32(cols),
            rows: UInt32(rows),
            cellWidth: UInt16(atlas.cellWidth),
            cellHeight: UInt16(atlas.cellHeight)
        )

        bridge?.onWakeup = { [weak self] in
            self?.needsRedraw = true
        }
    }

    /// Terminate the shell process and clean up.
    func terminate() {
        bridge = nil
        needsRedraw = true
    }

    // MARK: - Display Link

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        displayLink = link

        CVDisplayLinkSetOutputCallback(
            link, displayLinkFired,
            Unmanaged.passUnretained(self).toOpaque()
        )

        CVDisplayLinkStart(link)
    }

    fileprivate func displayLinkTick() {
        guard needsRedraw else { return }
        needsRedraw = false
        render()
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }

    // MARK: - Rendering

    private func render() {
        guard let drawable = metalLayer.nextDrawable() else { return }

        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = drawable.texture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(gridRenderer.defaultBg.x),
            green: Double(gridRenderer.defaultBg.y),
            blue: Double(gridRenderer.defaultBg.z),
            alpha: 1.0
        )

        // Take snapshot and update buffers
        if let bridge, let snapshot = bridge.snapshot() {
            gridRenderer.update(snapshot: snapshot)
            TerminalBridge.freeSnapshot(snapshot)
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }

        // Cell positions are in points (from CTFont metrics); viewport must match.
        // The Metal layer's contentsScale handles physical pixel resolution independently.
        let viewportSize = SIMD2<Float>(
            Float(bounds.width),
            Float(bounds.height)
        )

        gridRenderer.draw(encoder: encoder, viewportSize: viewportSize)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        let scale = metalLayer?.contentsScale ?? 2.0
        metalLayer?.drawableSize = CGSize(
            width: newSize.width * scale,
            height: newSize.height * scale
        )

        if let bridge, let atlas {
            let (cols, rows) = gridDimensions
            bridge.resize(
                cols: UInt32(cols), rows: UInt32(rows),
                cellWidth: UInt16(atlas.cellWidth),
                cellHeight: UInt16(atlas.cellHeight)
            )
        }

        needsRedraw = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2.0
        metalLayer?.contentsScale = scale
        metalLayer?.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        atlas?.setScale(scale)
        needsRedraw = true
    }

    // MARK: - Keyboard Input

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override func insertText(_ insertString: Any) {
        guard let str = insertString as? String else { return }

        if optionAsMeta && NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            bridge?.write("\u{1b}" + str)
        } else {
            bridge?.write(str)
        }
    }

    override func doCommand(by selector: Selector) {
        // Map AppKit selectors to terminal escape sequences
        let sequence: String? = switch selector {
        case #selector(moveUp(_:)):         "\u{1b}[A"
        case #selector(moveDown(_:)):       "\u{1b}[B"
        case #selector(moveRight(_:)):      "\u{1b}[C"
        case #selector(moveLeft(_:)):       "\u{1b}[D"
        case #selector(insertNewline(_:)):  "\r"
        case #selector(insertTab(_:)):      "\t"
        case #selector(cancelOperation(_:)): "\u{1b}"  // Escape key
        case #selector(deleteBackward(_:)): "\u{7f}"   // Backspace -> DEL
        case #selector(deleteForward(_:)):  "\u{1b}[3~"
        case #selector(insertBacktab(_:)):  "\u{1b}[Z" // Shift+Tab
        case #selector(moveToBeginningOfLine(_:)):   "\u{1b}[H"  // Home
        case #selector(moveToEndOfLine(_:)):         "\u{1b}[F"  // End
        case #selector(pageUp(_:)):         "\u{1b}[5~"
        case #selector(pageDown(_:)):       "\u{1b}[6~"
        default: nil
        }

        if let sequence {
            bridge?.write(sequence)
        }
    }

    // Handle Ctrl+key combinations
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.control),
              let chars = event.charactersIgnoringModifiers,
              let scalar = chars.unicodeScalars.first else {
            return super.performKeyEquivalent(with: event)
        }

        let value = scalar.value
        // Ctrl+A through Ctrl+Z (and some punctuation)
        if value >= UInt32(Character("a").asciiValue!) && value <= UInt32(Character("z").asciiValue!) {
            let ctrlChar = value - UInt32(Character("a").asciiValue!) + 1
            if let scalar = Unicode.Scalar(ctrlChar) {
                bridge?.write(String(Character(scalar)))
                return true
            }
        }

        // Ctrl+[ = ESC
        if chars == "[" {
            bridge?.write("\u{1b}")
            return true
        }

        // Ctrl+] = GS
        if chars == "]" {
            bridge?.write("\u{1d}")
            return true
        }

        // Ctrl+\\ = FS
        if chars == "\\" {
            bridge?.write("\u{1c}")
            return true
        }

        // Ctrl+C = ETX (0x03)
        if chars == "c" {
            bridge?.write("\u{03}")
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Mouse / Selection

    /// Whether a drag selection is in progress.
    private var isDragging = false

    /// Convert a mouse event location to grid (row, col, side).
    private func gridPosition(for event: NSEvent) -> (row: Int32, col: UInt32, side: SelectionSide) {
        let loc = convert(event.locationInWindow, from: nil)
        // NSView Y is bottom-up; grid row 0 is at the top
        let flippedY = bounds.height - loc.y
        let col = max(0, loc.x) / atlas.cellWidth
        let row = max(0, flippedY) / atlas.cellHeight
        // Side: left half of cell = .left, right half = .right
        let cellFraction = loc.x - CGFloat(Int(col)) * atlas.cellWidth
        let side: SelectionSide = cellFraction < atlas.cellWidth / 2 ? .left : .right
        return (Int32(row), UInt32(col), side)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        guard let bridge else { return }
        let (row, col, side) = gridPosition(for: event)

        let selectionType: SelectionKind = switch event.clickCount {
        case 2: .semantic  // Double-click: word
        case 3: .lines     // Triple-click: line
        default: .simple   // Single click: character
        }

        bridge.startSelection(row: row, col: col, side: side, type: selectionType)
        isDragging = true
        needsRedraw = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let bridge else { return }
        let (row, col, side) = gridPosition(for: event)
        bridge.updateSelection(row: row, col: col, side: side)
        needsRedraw = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    // MARK: - Focus

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func flagsChanged(with event: NSEvent) {
        // Could track modifier state if needed
    }
}
