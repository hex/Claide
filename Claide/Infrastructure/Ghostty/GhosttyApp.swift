// ABOUTME: Singleton owning the Ghostty terminal engine (ghostty_app_t).
// ABOUTME: Creates config, registers runtime callbacks, and routes actions to surfaces.

import AppKit
import GhosttyKit
import os

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
        ghostty_config_finalize(config)

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
            confirm_read_clipboard_cb: nil,
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
    }

    func shutdown() {
        if let app {
            ghostty_app_free(app)
        }
        self.app = nil
    }

    // MARK: - Tick

    private func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    /// Called from Zig IO thread — must not touch @MainActor state.
    fileprivate nonisolated static func wakeup() {
        DispatchQueue.main.async {
            guard let handle = appHandle else { return }
            ghostty_app_tick(handle)
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

        default:
            return false
        }
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
