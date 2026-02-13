// ABOUTME: Singleton owning the Ghostty terminal engine (ghostty_app_t).
// ABOUTME: Creates config, registers runtime callbacks, and routes actions to surfaces.

import AppKit
import Carbon.HIToolbox
import GhosttyKit
import os
import UserNotifications

// Free functions used as C callbacks — must not be @MainActor-isolated.
// Swift closures defined inside @MainActor methods inherit that isolation,
// which causes runtime assertion failures when called from background threads.

private func ghosttyWakeupCallback(_: UnsafeMutableRawPointer?) {
    DispatchQueue.main.async {
        guard let handle = GhosttyApp.appHandle else { return }
        ghostty_app_tick(handle)
    }
}

private func ghosttyActionCallback(
    _ appHandle: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    guard let appHandle else { return false }
    return GhosttyApp.handleAction(appHandle, target: target, action: action)
}

private func ghosttyReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) {
    GhosttyApp.readClipboard(userdata, location: location, state: state)
}

private func ghosttyConfirmReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ str: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
    GhosttyApp.confirmReadClipboard(userdata, str: str, state: state, request: request)
}

private func ghosttyWriteClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ string: UnsafePointer<CChar>?,
    _ location: ghostty_clipboard_e,
    _ confirm: Bool
) {
    GhosttyApp.writeClipboard(userdata, string: string, location: location, confirm: confirm)
}

private func ghosttyCloseSurfaceCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ processAlive: Bool
) {
    GhosttyApp.closeSurface(userdata, processAlive: processAlive)
}

@MainActor
final class GhosttyApp {

    static let shared = GhosttyApp()

    /// Accessed from any thread by the wakeup callback; safe because
    /// ghostty_app_t is an opaque pointer that Ghostty synchronizes internally.
    nonisolated(unsafe) static var appHandle: ghostty_app_t?

    private(set) var app: ghostty_app_t? {
        didSet { Self.appHandle = app }
    }
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.hexul.claide", category: "ghostty")

    /// Terminal background color read from Ghostty's finalized config.
    /// Used by Theme and TerminalTheme so chrome colors match the terminal.
    /// nonisolated(unsafe) because it's written once during start() and then only read.
    nonisolated(unsafe) static var backgroundColor: NSColor = NSColor(srgbRed: 0x28/255.0, green: 0x2C/255.0, blue: 0x34/255.0, alpha: 1)

    /// Terminal foreground color read from Ghostty's finalized config.
    nonisolated(unsafe) static var foregroundColor: NSColor = NSColor(srgbRed: 0xAB/255.0, green: 0xB2/255.0, blue: 0xBF/255.0, alpha: 1)

    private init() {}

    // MARK: - Lifecycle

    /// Initialize the Ghostty engine with default configuration.
    func start() {
        guard app == nil else { return }

        // Initialize Zig standard library global state (allocators, thread pools).
        // Must be called before any other ghostty_* function.
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            logger.error("ghostty_init failed")
            return
        }

        guard let config = ghostty_config_new() else {
            logger.error("ghostty_config_new failed")
            return
        }

        // Load default config from ~/.config/ghostty/config if it exists
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        applySettingsOverrides(config)
        ghostty_config_finalize(config)

        // Read terminal colors from finalized config so chrome matches.
        readConfigColors(config)

        // Log any config diagnostics
        let diagCount = ghostty_config_diagnostics_count(config)
        for i in 0..<diagCount {
            let diag = ghostty_config_get_diagnostic(config, i)
            if let msg = diag.message {
                logger.warning("Config: \(String(cString: msg))")
            }
        }

        // The runtime config defines how Ghostty communicates with the host app.
        // wakeup_cb receives the app userdata; clipboard/close callbacks receive
        // the surface userdata (the GhosttyTerminalView).
        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: ghosttyWakeupCallback,
            action_cb: ghosttyActionCallback,
            read_clipboard_cb: ghosttyReadClipboardCallback,
            confirm_read_clipboard_cb: ghosttyConfirmReadClipboardCallback,
            write_clipboard_cb: ghosttyWriteClipboardCallback,
            close_surface_cb: ghosttyCloseSurfaceCallback
        )

        guard let newApp = ghostty_app_new(&runtimeConfig, config) else {
            logger.error("ghostty_app_new failed")
            ghostty_config_free(config)
            return
        }

        self.app = newApp
        logger.info("Ghostty engine started")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardLayoutChanged),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )
        observeGhosttySettings()
    }

    @objc private func keyboardLayoutChanged(_ notification: Notification) {
        guard let app else { return }
        ghostty_app_keyboard_changed(app)
    }

    func shutdown() {
        if let app {
            ghostty_app_free(app)
        }
        self.app = nil
    }

    // MARK: - Settings Bridge

    /// Push a key-value pair into a Ghostty config object before finalization.
    private func configSet(_ config: ghostty_config_t, key: String, value: String) {
        key.withCString { keyPtr in
            value.withCString { valPtr in
                ghostty_config_set(config, keyPtr, UInt(key.utf8.count), valPtr, UInt(value.utf8.count))
            }
        }
    }

    /// Apply UserDefaults overrides to a Ghostty config (before finalize).
    private func applySettingsOverrides(_ config: ghostty_config_t) {
        let defaults = UserDefaults.standard

        let fontFamily = defaults.string(forKey: "fontFamily") ?? ""
        if !fontFamily.isEmpty {
            configSet(config, key: "font-family", value: "")        // Reset RepeatableString
            configSet(config, key: "font-family", value: fontFamily)
        }

        let fontSize = defaults.double(forKey: "terminalFontSize")
        if fontSize > 0 {
            configSet(config, key: "font-size", value: String(Int(fontSize)))
        }

        let scrollback = defaults.integer(forKey: "scrollbackLines")
        if scrollback > 0 {
            configSet(config, key: "scrollback-limit", value: String(scrollback))
        }

        if defaults.object(forKey: "copyOnSelect") != nil {
            let copyOnSelect = defaults.bool(forKey: "copyOnSelect")
            configSet(config, key: "copy-on-select", value: copyOnSelect ? "true" : "false")
        }
    }

    /// Rebuild the full config from disk + UserDefaults and push to Ghostty.
    func reloadConfig() {
        guard let app else { return }
        guard let config = ghostty_config_new() else { return }

        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        applySettingsOverrides(config)
        ghostty_config_finalize(config)

        readConfigColors(config)
        ghostty_app_update_config(app, config)
        // ghostty_app_update_config takes ownership — do NOT free config
    }

    private var settingsObservation: Any?

    private func observeGhosttySettings() {
        settingsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadConfig()
        }
    }

    // MARK: - Config Colors

    /// Read background and foreground from Ghostty's finalized config.
    /// Must be called after ghostty_config_finalize and before ghostty_app_new
    /// consumes the config.
    private func readConfigColors(_ config: ghostty_config_t) {
        var bg = ghostty_config_color_s(r: 0, g: 0, b: 0)
        if ghostty_config_get(config, &bg, "background", 10) {
            Self.backgroundColor = NSColor(
                srgbRed: CGFloat(bg.r) / 255,
                green: CGFloat(bg.g) / 255,
                blue: CGFloat(bg.b) / 255,
                alpha: 1
            )
        }

        var fg = ghostty_config_color_s(r: 0, g: 0, b: 0)
        if ghostty_config_get(config, &fg, "foreground", 10) {
            Self.foregroundColor = NSColor(
                srgbRed: CGFloat(fg.r) / 255,
                green: CGFloat(fg.g) / 255,
                blue: CGFloat(fg.b) / 255,
                alpha: 1
            )
        }
    }

    // MARK: - Action Routing

    fileprivate nonisolated static func handleAction(
        _ appHandle: ghostty_app_t,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        // Route surface-targeted actions to the appropriate GhosttyTerminalView
        if target.tag == GHOSTTY_TARGET_SURFACE {
            let surface = target.target.surface
            guard let view = GhosttyTerminalView.view(for: surface) else { return false }

            switch action.tag {
            case GHOSTTY_ACTION_SET_TITLE:
                let title = action.action.set_title.title.map { String(cString: $0) }
                if let title {
                    DispatchQueue.main.async { view.onTitle?(title) }
                }
                return true

            case GHOSTTY_ACTION_PWD:
                let pwd = action.action.pwd.pwd.map { String(cString: $0) }
                if let pwd {
                    DispatchQueue.main.async { view.onDirectoryChange?(pwd) }
                }
                return true

            case GHOSTTY_ACTION_RING_BELL:
                DispatchQueue.main.async { view.onBell?() }
                return true

            case GHOSTTY_ACTION_MOUSE_SHAPE:
                DispatchQueue.main.async { view.updateMouseCursor(action.action.mouse_shape) }
                return true

            case GHOSTTY_ACTION_RENDER:
                // Ghostty handles rendering internally
                return true

            case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
                let exitCode = Int32(action.action.child_exited.exit_code)
                DispatchQueue.main.async { view.onChildExit?(exitCode) }
                return true

            case GHOSTTY_ACTION_PROGRESS_REPORT:
                let report = action.action.progress_report
                DispatchQueue.main.async {
                    view.onProgressReport?(UInt8(report.state.rawValue), Int32(report.progress))
                }
                return true

            case GHOSTTY_ACTION_COLOR_CHANGE:
                // Terminal-initiated color change (e.g. OSC 10/11)
                return true

            case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
                let notification = action.action.desktop_notification
                let title = String(cString: notification.title)
                let body = String(cString: notification.body)
                DispatchQueue.main.async {
                    GhosttyApp.postDesktopNotification(title: title, body: body)
                }
                return true

            case GHOSTTY_ACTION_OPEN_URL:
                let openUrl = action.action.open_url
                let raw = UnsafeRawBufferPointer(
                    start: openUrl.url,
                    count: Int(openUrl.len)
                )
                let urlString = String(bytes: raw, encoding: .utf8)
                if let urlString, let url = URL(string: urlString) {
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                }
                return true

            case GHOSTTY_ACTION_MOUSE_OVER_LINK:
                let link = action.action.mouse_over_link
                let hasUrl = link.len > 0
                DispatchQueue.main.async {
                    if hasUrl {
                        NSCursor.pointingHand.set()
                    } else {
                        NSCursor.iBeam.set()
                    }
                }
                return true

            case GHOSTTY_ACTION_SECURE_INPUT:
                let mode = action.action.secure_input
                DispatchQueue.main.async {
                    switch mode {
                    case GHOSTTY_SECURE_INPUT_ON:
                        EnableSecureEventInput()
                    case GHOSTTY_SECURE_INPUT_OFF:
                        DisableSecureEventInput()
                    case GHOSTTY_SECURE_INPUT_TOGGLE:
                        if IsSecureEventInputEnabled() {
                            DisableSecureEventInput()
                        } else {
                            EnableSecureEventInput()
                        }
                    default:
                        break
                    }
                }
                return true

            default:
                return false
            }
        }

        // App-level actions — we handle window/tab management ourselves
        switch action.tag {
        case GHOSTTY_ACTION_QUIT,
             GHOSTTY_ACTION_NEW_WINDOW,
             GHOSTTY_ACTION_NEW_TAB,
             GHOSTTY_ACTION_NEW_SPLIT:
            return true

        case GHOSTTY_ACTION_CONFIG_CHANGE:
            // Ghostty reloaded its config; acknowledged but no action needed.
            // The embedded runtime manages config internally.
            return true

        default:
            return false
        }
    }

    // MARK: - Desktop Notifications

    private static func postDesktopNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Clipboard Callbacks
    //
    // Clipboard and close callbacks receive surface userdata (GhosttyTerminalView),
    // NOT app userdata.

    fileprivate nonisolated static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        guard let userdata else { return }
        let view = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.surface else { return }

        let pasteboard = NSPasteboard.general
        let str = pasteboard.string(forType: .string) ?? ""
        str.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
    }

    fileprivate nonisolated static func confirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        str: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let userdata, let str else { return }
        let view = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
        let contents = String(cString: str)

        // Wrap the opaque pointer so it can cross the isolation boundary.
        // The pointer is owned by Ghostty and valid until we call complete.
        nonisolated(unsafe) let sendableState = state

        DispatchQueue.main.async {
            guard let surface = view.surface else { return }
            guard let window = view.window else {
                "".withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, sendableState, false)
                }
                return
            }

            let alert = NSAlert()
            switch request {
            case GHOSTTY_CLIPBOARD_REQUEST_PASTE:
                alert.messageText = "Confirm Paste"
                alert.informativeText = "A program wants to paste the following content:\n\n\(contents.prefix(500))"
            case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ:
                alert.messageText = "Clipboard Access"
                alert.informativeText = "A program wants to read your clipboard:\n\n\(contents.prefix(500))"
            case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE:
                alert.messageText = "Clipboard Write"
                alert.informativeText = "A program wants to write to your clipboard:\n\n\(contents.prefix(500))"
            default:
                alert.messageText = "Clipboard Access"
                alert.informativeText = "A program wants to access your clipboard."
            }
            alert.addButton(withTitle: "Allow")
            alert.addButton(withTitle: "Deny")
            alert.alertStyle = .warning

            alert.beginSheetModal(for: window) { response in
                let confirmed = response == .alertFirstButtonReturn
                let data = confirmed ? contents : ""
                data.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, sendableState, confirmed)
                }
            }
        }
    }

    fileprivate nonisolated static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        location: ghostty_clipboard_e,
        confirm: Bool
    ) {
        guard let string else { return }
        let text = String(cString: string)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    fileprivate nonisolated static func closeSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        guard let userdata else { return }
        let view = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
        DispatchQueue.main.async {
            view.onChildExit?(0)
        }
    }
}
