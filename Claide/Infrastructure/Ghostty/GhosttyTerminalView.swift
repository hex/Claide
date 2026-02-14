// ABOUTME: NSView hosting a Ghostty terminal surface with Metal rendering.
// ABOUTME: Handles input, resize, focus, and routes terminal events to callbacks.

import AppKit
import GhosttyKit
import os

/// Terminal view backed by Ghostty's Metal renderer and VTE engine.
///
/// Ghostty owns the CAMetalLayer, PTY, and parsing. This view forwards input
/// events and sizing, and receives terminal state via action callbacks.
final class GhosttyTerminalView: NSView {

    // MARK: - Static Surface Registry

    /// Maps surface pointers to views for action callback routing.
    private static var surfaceRegistry: [UnsafeMutableRawPointer: GhosttyTerminalView] = [:]

    static func view(for surface: ghostty_surface_t?) -> GhosttyTerminalView? {
        guard let surface else { return nil }
        let ptr = unsafeBitCast(surface, to: UnsafeMutableRawPointer.self)
        return surfaceRegistry[ptr]
    }

    private func registerSurface() {
        guard let surface else { return }
        let ptr = unsafeBitCast(surface, to: UnsafeMutableRawPointer.self)
        Self.surfaceRegistry[ptr] = self
    }

    private func unregisterSurface() {
        guard let surface else { return }
        let ptr = unsafeBitCast(surface, to: UnsafeMutableRawPointer.self)
        Self.surfaceRegistry.removeValue(forKey: ptr)
    }

    // MARK: - Properties

    private(set) var surface: ghostty_surface_t?
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.hexul.claide", category: "ghostty-surface")

    // Terminal event callbacks
    var onTitle: ((String) -> Void)?
    var onDirectoryChange: ((String) -> Void)?
    var onChildExit: ((Int32) -> Void)?
    var onBell: (() -> Void)?
    var onFocused: (() -> Void)?
    var onProgressReport: ((UInt8, Int32) -> Void)?

    /// Stored content size for backing property changes.
    private var contentSize: CGSize = .zero

    /// Drives layer redisplay for frames rendered by Ghostty's async path.
    /// In a layer-hosting view, setting layer.contents via dispatch_async
    /// does not automatically trigger Core Animation composition.
    private var displayRefreshTimer: Timer?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Do NOT set wantsLayer here. Ghostty's Metal renderer creates an
        // IOSurfaceLayer and assigns it to view.layer BEFORE setting
        // wantsLayer = true, making this a "layer-hosting" view. Pre-setting
        // wantsLayer would make it "layer-backed" instead, which prevents
        // Ghostty from properly owning the Metal layer.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Shell Lifecycle

    /// Create a Ghostty surface and start a shell.
    ///
    /// Ghostty owns the PTY and shell process — there's no separate startShell step.
    /// Call this once after the view is laid out with a non-zero frame.
    ///
    /// Ghostty determines the shell from the SHELL environment variable (pass it
    /// in `environment`). On macOS it launches via `login(1)` for a proper login
    /// shell with hushlogin support.
    func startShell(
        environment: [(String, String)],
        directory: String
    ) {
        guard let app = GhosttyApp.shared.app else {
            logger.error("GhosttyApp not started")
            return
        }
        guard surface == nil else {
            logger.warning("Surface already created")
            return
        }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(
            nsview: Unmanaged.passUnretained(self).toOpaque()
        ))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()

        // Scale factor from current screen
        if let screen = window?.screen ?? NSScreen.main {
            config.scale_factor = Double(screen.backingScaleFactor)
        } else {
            config.scale_factor = 2.0
        }

        // Convert environment to ghostty_env_var_s array
        var envVars: [ghostty_env_var_s] = []
        var envKeyStorage: [UnsafeMutablePointer<CChar>] = []
        var envValueStorage: [UnsafeMutablePointer<CChar>] = []

        for (key, value) in environment {
            let cKey = strdup(key)!
            let cValue = strdup(value)!
            envKeyStorage.append(cKey)
            envValueStorage.append(cValue)
            envVars.append(ghostty_env_var_s(key: cKey, value: cValue))
        }

        defer {
            envKeyStorage.forEach { free($0) }
            envValueStorage.forEach { free($0) }
        }

        directory.withCString { cDir in
            config.working_directory = cDir

            envVars.withUnsafeMutableBufferPointer { envBuf in
                config.env_vars = envBuf.baseAddress
                config.env_var_count = envBuf.count

                self.surface = ghostty_surface_new(app, &config)
            }
        }

        guard surface != nil else {
            logger.error("ghostty_surface_new failed")
            return
        }

        registerSurface()
        updateTrackingAreas()
        setupDragAndDrop()
        startDisplayRefresh()
    }

    /// Destroy the terminal surface and clean up.
    func terminate() {
        displayRefreshTimer?.invalidate()
        displayRefreshTimer = nil
        unregisterSurface()
        if let surface {
            ghostty_surface_free(surface)
        }
        surface = nil
    }

    deinit {
        // terminate() must be called before deallocation.
        // NSView always deallocates on main thread; this is a safety net.
        MainActor.assumeIsolated {
            displayRefreshTimer?.invalidate()
            if surface != nil {
                unregisterSurface()
                ghostty_surface_free(surface!)
            }
        }
    }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let surface = self.surface, let window = self.window {
            let fbFrame = self.convertToBacking(self.frame)
            ghostty_surface_set_size(surface, UInt32(fbFrame.width), UInt32(fbFrame.height))
            syncDisplayId()

            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: nil)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidChangeScreen),
                name: NSWindow.didChangeScreenNotification,
                object: window
            )
        }
    }

    @objc private func windowDidChangeScreen(_ notification: Notification) {
        syncDisplayId()
    }

    /// Tell Ghostty which physical display this surface is on so the
    /// Metal renderer can match the display's refresh rate and color profile.
    private func syncDisplayId() {
        guard let surface, let screen = window?.screen else { return }
        let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        ghostty_surface_set_display_id(surface, displayId)
    }

    /// Tell Core Animation to re-composite the layer at display refresh rate.
    ///
    /// Ghostty's renderer thread draws frames to IOSurface objects and sets
    /// them as layer.contents via dispatch_async. In a layer-hosting view,
    /// this does not automatically trigger a composition pass. We compensate
    /// by periodically marking the layer as needing display.
    private func startDisplayRefresh() {
        displayRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.layer?.setNeedsDisplay()
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onFocused?()
            if let surface {
                ghostty_surface_set_focus(surface, true)
            }
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    // MARK: - Sizing

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let surface, newSize.width > 0, newSize.height > 0 else { return }
        contentSize = newSize
        let scaled = convertToBacking(newSize)
        ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface, let window else { return }

        layer?.contentsScale = window.backingScaleFactor

        let fbFrame = convertToBacking(frame)
        let xScale = fbFrame.size.width / frame.size.width
        let yScale = fbFrame.size.height / frame.size.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)

        let scaled = convertToBacking(contentSize)
        ghostty_surface_set_size(surface, UInt32(scaled.width), UInt32(scaled.height))
    }

    // MARK: - Occlusion

    func setOccluded(_ occluded: Bool) {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, occluded)
    }

    // MARK: - Actions (Copy/Paste/Select/Font)

    /// Dispatch a Ghostty binding action by name.
    private func bindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return ghostty_surface_binding_action(surface, action, UInt(action.count))
    }

    @IBAction func copy(_ sender: Any?) {
        _ = bindingAction("copy_to_clipboard")
    }

    @IBAction func paste(_ sender: Any?) {
        _ = bindingAction("paste_from_clipboard")
    }

    @IBAction override func selectAll(_ sender: Any?) {
        _ = bindingAction("select_all")
    }

    func increaseFontSize(amount: Int = 1) {
        _ = bindingAction("increase_font_size:\(amount)")
    }

    func decreaseFontSize(amount: Int = 1) {
        _ = bindingAction("decrease_font_size:\(amount)")
    }

    func resetFontSize() {
        _ = bindingAction("reset_font_size")
    }

    // MARK: - Mouse Cursor

    func updateMouseCursor(_ shape: ghostty_action_mouse_shape_e) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT:
            NSCursor.arrow.set()
        case GHOSTTY_MOUSE_SHAPE_TEXT:
            NSCursor.iBeam.set()
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            NSCursor.pointingHand.set()
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
            NSCursor.crosshair.set()
        default:
            NSCursor.arrow.set()
        }
    }

    // MARK: - Drag and Drop

    func setupDragAndDrop() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else {
            return []
        }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let surface,
              let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
              ) as? [URL] else { return false }

        let paths = urls.map { shellEscape($0.path) }
        let text = paths.joined(separator: " ")
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
        return true
    }

    private func shellEscape(_ path: String) -> String {
        // Single-quote wrapping with internal single-quote escaping
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        super.updateTrackingAreas()
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard surface != nil else {
            interpretKeyEvents([event])
            return
        }

        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        let markedBefore = markedText.length > 0
        interpretKeyEvents([event])
        syncPreedit(clearIfNeeded: markedBefore)

        if let list = keyTextAccumulator, !list.isEmpty {
            for text in list {
                _ = sendKeyEvent(action, event: event, text: text)
            }
        } else {
            _ = sendKeyEvent(
                action,
                event: event,
                text: ghosttyCharacters(from: event),
                composing: markedText.length > 0 || markedBefore
            )
        }
    }

    // Absorb command selectors (moveUp:, deleteBackward:, etc.) dispatched
    // by interpretKeyEvents for arrow keys, backspace, etc. Without this
    // override, NSView forwards to noResponder(for:) which plays the
    // system alert sound.
    override func doCommand(by selector: Selector) {}

    override func keyUp(with event: NSEvent) {
        guard surface != nil else { return }
        _ = sendKeyEvent(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard surface != nil else { return }
        if markedText.length > 0 { return }

        let mods = ghosttyMods(from: event.modifierFlags)
        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        let action: ghostty_input_action_e = (mods.rawValue & mod != 0)
            ? GHOSTTY_ACTION_PRESS
            : GHOSTTY_ACTION_RELEASE

        _ = sendKeyEvent(action, event: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let Claide handle Cmd+key shortcuts
        if event.modifierFlags.contains(.command) {
            return false
        }
        return super.performKeyEquivalent(with: event)
    }

    private func sendKeyEvent(
        _ action: ghostty_input_action_e,
        event: NSEvent,
        text: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.mods = ghosttyMods(from: event.modifierFlags)
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.composing = composing

        // Control and command never contribute to text translation
        keyEvent.consumed_mods = ghosttyMods(
            from: event.modifierFlags.subtracting([.control, .command])
        )

        // Unshifted codepoint: the character with no modifiers applied.
        // Ghostty uses this for keybinding matching and encoding.
        if event.type == .keyDown || event.type == .keyUp {
            if let chars = event.characters(byApplyingModifiers: []),
               let codepoint = chars.unicodeScalars.first {
                keyEvent.unshifted_codepoint = codepoint.value
            }
        }

        // Only pass text if the first byte is not a control character —
        // Ghostty's KeyEncoder handles control character encoding internally.
        if let text, !text.isEmpty,
           let firstByte = text.utf8.first, firstByte >= 0x20 {
            return text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        }

        return ghostty_surface_key(surface, keyEvent)
    }

    /// Compute the text to send with a key event.
    /// For control characters (value < 0x20), returns the character without Ctrl
    /// applied so Ghostty's KeyEncoder can handle control encoding itself.
    /// Returns nil for function keys in the Private Use Area.
    private func ghosttyCharacters(from event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }

        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface else { return }
        let mods = ghosttyMods(from: event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = ghosttyMods(from: event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)
    }

    override func rightMouseDown(with event: NSEvent) {
        if UserDefaults.standard.bool(forKey: "pasteOnRightClick") {
            _ = bindingAction("paste_from_clipboard")
            return
        }
        guard let surface else { return }
        let mods = ghosttyMods(from: event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface else { return }
        let mods = ghosttyMods(from: event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, mods)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        let pasteItem = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        pasteItem.target = self
        menu.addItem(pasteItem)
        menu.addItem(.separator())
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
        selectAllItem.target = self
        menu.addItem(selectAllItem)
        return menu
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        let mods = ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        let mods = ghosttyMods(from: event.modifierFlags)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, mods)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            x *= 2
            y *= 2
        }
        // ghostty_input_scroll_mods_t is an int bitmask
        let scrollMods: ghostty_input_scroll_mods_t = event.hasPreciseScrollingDeltas ? 1 : 0
        ghostty_surface_mouse_scroll(surface, x, y, scrollMods)
    }

    // MARK: - Modifier Conversion

    private func ghosttyMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = 0
        if flags.contains(.shift)   { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option)  { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    // MARK: - IME (NSTextInputClient)

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            markedText.string.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(markedText.string.utf8.count))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }
}

// MARK: - NSTextInputClient

extension GhosttyTerminalView: @preconcurrency NSTextInputClient {

    func insertText(_ string: Any, replacementRange: NSRange) {
        var chars = ""
        switch string {
        case let s as NSAttributedString: chars = s.string
        case let s as String: chars = s
        default: return
        }

        unmarkText()

        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            return
        }

        // Direct text insertion (e.g. paste via IME)
        guard let surface else { return }
        chars.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(chars.utf8.count))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let s as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: s)
        case let s as String:
            markedText = NSMutableAttributedString(string: s)
        default: return
        }

        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        markedText.mutableString.setString("")
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        if markedText.length > 0 {
            return NSRange(location: 0, length: markedText.length)
        }
        return NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributedString(for string: NSAttributedString) -> NSAttributedString {
        string
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Return a position near the cursor for IME candidate window placement
        guard let window else { return .zero }
        let screenFrame = window.convertToScreen(convert(bounds, to: nil))
        return NSRect(x: screenFrame.origin.x, y: screenFrame.origin.y, width: 0, height: 0)
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedString() -> NSAttributedString {
        NSAttributedString()
    }

    func fractionOfDistanceThroughGlyph(for point: NSPoint) -> CGFloat {
        0
    }

    func baselineDeltaForCharacter(at index: Int) -> CGFloat {
        0
    }

    func windowLevel() -> Int {
        guard let window else { return 0 }
        return Int(window.level.rawValue)
    }

    func drawsVerticallyForCharacter(at index: Int) -> Bool {
        false
    }
}
