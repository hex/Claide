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

    /// Current font. Changing this re-rasterizes glyphs immediately for visual
    /// feedback, then schedules a debounced grid resize to match.
    var terminalFont: NSFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) {
        didSet {
            atlas?.setFont(terminalFont)
            needsRedraw = true
            debouncedResize()
        }
    }

    /// Last grid dimensions sent to the terminal bridge, used to avoid redundant reflows.
    private var currentCols = 0
    private var currentRows = 0

    /// Pending font-zoom resize work item (debounced to coalesce rapid Cmd+=/Cmd+- presses).
    private var resizeDebounceWork: DispatchWorkItem?

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

    /// Cursor shape rendered by the view (overrides the terminal emulator's shape).
    enum CursorShape: UInt8 {
        case block = 0
        case underline = 1
        case beam = 2
    }

    private(set) var cursorShape: CursorShape = .beam
    private(set) var cursorBlinking: Bool = true

    /// IME marked text state (for NSTextInputClient).
    private var markedTextStorage = NSMutableAttributedString()
    private var markedRangeStorage = NSRange(location: NSNotFound, length: 0)

    /// Cursor blink state and timer (~530ms period, matching iTerm2/Alacritty convention).
    private var cursorBlinkOn = true
    private var cursorBlinkTimer: Timer?

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

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Metal shader library not found in app bundle")
        }
        do {
            gridRenderer = try GridRenderer(device: device, atlas: atlas, library: library)
        } catch {
            fatalError("Failed to create GridRenderer: \(error)")
        }

        startDisplayLink()
    }

    deinit {
        stopCursorBlink()
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

        startCursorBlink()
    }

    /// Terminate the shell process and clean up.
    func terminate() {
        stopCursorBlink()
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

    // MARK: - Cursor Preferences

    /// Apply cursor shape and blink settings from the UI.
    func applyCursorPreferences(shape: CursorShape, blinking: Bool) {
        cursorShape = shape
        cursorBlinking = blinking
        if blinking {
            if cursorBlinkTimer == nil { startCursorBlink() }
        } else {
            stopCursorBlink()
            cursorBlinkOn = true
        }
        needsRedraw = true
    }

    // MARK: - Cursor Blink

    private func startCursorBlink() {
        cursorBlinkOn = true
        cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            self?.cursorBlinkOn.toggle()
            self?.needsRedraw = true
        }
    }

    private func stopCursorBlink() {
        cursorBlinkTimer?.invalidate()
        cursorBlinkTimer = nil
    }

    /// Reset blink cycle so the cursor is visible immediately after input.
    private func resetCursorBlink() {
        guard cursorBlinking else { return }
        cursorBlinkOn = true
        cursorBlinkTimer?.fireDate = Date(timeIntervalSinceNow: 0.53)
        needsRedraw = true
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
            // Apply user's cursor shape preference
            snapshot.pointee.cursor.shape = cursorShape.rawValue
            // Hide cursor during blink-off phase
            if cursorBlinking && !cursorBlinkOn {
                snapshot.pointee.cursor.visible = false
            }
            // Bottom-align the grid so the prompt stays visible when the grid
            // (at the current font size) extends beyond the view bounds.
            let gridPixelHeight = Float(snapshot.pointee.rows) * Float(atlas.cellHeight)
            let yOffset = max(0, gridPixelHeight - Float(bounds.height))
            gridRenderer.update(snapshot: snapshot, yOffset: yOffset)
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
            if cols != currentCols || rows != currentRows {
                currentCols = cols
                currentRows = rows
                // No-reflow resize: updates grid dimensions, scroll region, tabs, and
                // damage without rewrapping content. Avoids lossy reflow of powerline
                // prompts and other exact-width content.
                bridge.resizeGridNoReflow(cols: UInt32(cols), rows: UInt32(rows))
                if !inLiveResize {
                    bridge.notifyPtySize(
                        cols: UInt32(cols), rows: UInt32(rows),
                        cellWidth: UInt16(atlas.cellWidth),
                        cellHeight: UInt16(atlas.cellHeight)
                    )
                }
            }
        }

        needsRedraw = true
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        // Grid is already at the correct dimensions from setFrameSize calls.
        // Send SIGWINCH so the shell redraws for the new size.
        guard let bridge, let atlas else { return }
        bridge.notifyPtySize(
            cols: UInt32(currentCols), rows: UInt32(currentRows),
            cellWidth: UInt16(atlas.cellWidth),
            cellHeight: UInt16(atlas.cellHeight)
        )
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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    // MARK: - Keyboard Input

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        resetCursorBlink()

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Option-as-Meta: send ESC + char directly, bypassing the input method
        if optionAsMeta && flags.contains(.option)
            && !flags.contains(.command) && !flags.contains(.control) {
            if let chars = event.charactersIgnoringModifiers {
                bridge?.write("\u{1b}" + chars)
            }
            return
        }

        interpretKeyEvents([event])
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let chars = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }

        // Cmd+key: font size adjustment
        if flags == .command || flags == [.command, .shift] {
            switch chars {
            case "=", "+":
                adjustFontSize(by: 1)
                return true
            case "-":
                if flags == .command {
                    adjustFontSize(by: -1)
                    return true
                }
            case "0":
                if flags == .command {
                    resetFontSize()
                    return true
                }
            default:
                break
            }
        }

        // Ctrl+key combinations
        guard flags == .control, let scalar = chars.unicodeScalars.first else {
            return super.performKeyEquivalent(with: event)
        }

        let value = scalar.value
        // Ctrl+A through Ctrl+Z
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

        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Font Size

    private static var defaultFontSize: CGFloat {
        let size = UserDefaults.standard.double(forKey: "terminalFontSize")
        return size > 0 ? size : 14
    }
    private static let minFontSize: CGFloat = 8
    private static let maxFontSize: CGFloat = 72

    private func adjustFontSize(by delta: CGFloat) {
        let newSize = min(Self.maxFontSize, max(Self.minFontSize, terminalFont.pointSize + delta))
        guard newSize != terminalFont.pointSize else { return }
        terminalFont = NSFont(descriptor: terminalFont.fontDescriptor, size: newSize)
            ?? NSFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
    }

    private func resetFontSize() {
        terminalFont = NSFont(descriptor: terminalFont.fontDescriptor, size: Self.defaultFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: Self.defaultFontSize, weight: .regular)
    }

    /// Schedule a grid resize after a short delay to coalesce rapid font size changes.
    /// The atlas is already updated (immediate visual feedback); this adapts the grid.
    private func debouncedResize() {
        resizeDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let bridge, let atlas else { return }
            let (cols, rows) = self.gridDimensions
            if cols != self.currentCols || rows != self.currentRows {
                self.currentCols = cols
                self.currentRows = rows
                bridge.resize(
                    cols: UInt32(cols), rows: UInt32(rows),
                    cellWidth: UInt16(atlas.cellWidth),
                    cellHeight: UInt16(atlas.cellHeight)
                )
                self.needsRedraw = true
            }
        }
        resizeDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
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
        resetCursorBlink()

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

    // MARK: - Standard Edit Actions

    @objc func copy(_ sender: Any?) {
        guard let text = bridge?.selectedText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        bridge?.clearSelection()
        needsRedraw = true
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        bridge?.write(text)
    }

    @objc override func selectAll(_ sender: Any?) {
        guard let bridge else { return }
        let (cols, rows) = gridDimensions
        bridge.startSelection(row: 0, col: 0, side: .left, type: .simple)
        bridge.updateSelection(row: Int32(rows - 1), col: UInt32(cols - 1), side: .right)
        needsRedraw = true
    }

    @objc private func clearSelection(_ sender: Any?) {
        bridge?.clearSelection()
        needsRedraw = true
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)):
            return bridge?.selectedText() != nil
        case #selector(paste(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        case #selector(selectAll(_:)):
            return bridge != nil
        case #selector(clearSelection(_:)):
            return bridge?.selectedText() != nil
        default:
            return true
        }
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = .command
        menu.addItem(pasteItem)

        menu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        menu.addItem(selectAllItem)

        let clearSelItem = NSMenuItem(title: "Clear Selection", action: #selector(clearSelection(_:)), keyEquivalent: "")
        menu.addItem(clearSelItem)

        return menu
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

// MARK: - NSTextInputClient

extension MetalTerminalView: @preconcurrency NSTextInputClient {

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let s = string as? String {
            text = s
        } else if let attr = string as? NSAttributedString {
            text = attr.string
        } else {
            return
        }

        // Clear any IME composition state
        markedTextStorage.mutableString.setString("")
        markedRangeStorage = NSRange(location: NSNotFound, length: 0)

        bridge?.write(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attr = string as? NSAttributedString {
            markedTextStorage = NSMutableAttributedString(attributedString: attr)
        } else if let s = string as? String {
            markedTextStorage = NSMutableAttributedString(string: s)
        }

        if markedTextStorage.length > 0 {
            markedRangeStorage = NSRange(location: 0, length: markedTextStorage.length)
        } else {
            markedRangeStorage = NSRange(location: NSNotFound, length: 0)
        }

        needsRedraw = true
    }

    func unmarkText() {
        markedTextStorage.mutableString.setString("")
        markedRangeStorage = NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        markedRangeStorage
    }

    func hasMarkedText() -> Bool {
        markedTextStorage.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Position the IME candidate window at the terminal cursor
        guard let bridge, let snapshot = bridge.snapshot() else { return .zero }
        let cursor = snapshot.pointee.cursor
        TerminalBridge.freeSnapshot(snapshot)

        let x = CGFloat(cursor.col) * atlas.cellWidth
        let y = bounds.height - CGFloat(cursor.row + 1) * atlas.cellHeight
        let rect = NSRect(x: x, y: y, width: atlas.cellWidth, height: atlas.cellHeight)
        return window?.convertToScreen(convert(rect, to: nil)) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }
}
