// ABOUTME: Singleton owning the Ghostty terminal engine (ghostty_app_t).
// ABOUTME: Creates config, registers runtime callbacks, and routes actions to surfaces.

import AppKit
import GhosttyKit
import os

@MainActor
final class GhosttyApp {

    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.hexul.claide", category: "ghostty")

    private init() {}

    // MARK: - Lifecycle

    /// Initialize the Ghostty engine with default configuration.
    func start() {
        guard app == nil else { return }

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
            wakeup_cb: { userdata in
                guard let userdata else { return }
                let app = Unmanaged<GhosttyApp>.fromOpaque(userdata).takeUnretainedValue()
                DispatchQueue.main.async { app.tick() }
            },
            action_cb: { appHandle, target, action in
                guard let appHandle else { return false }
                return GhosttyApp.handleAction(appHandle, target: target, action: action)
            },
            read_clipboard_cb: { userdata, location, state in
                GhosttyApp.readClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: nil,
            write_clipboard_cb: { userdata, string, location, confirm in
                GhosttyApp.writeClipboard(userdata, string: string, location: location, confirm: confirm)
            },
            close_surface_cb: { userdata, processAlive in
                GhosttyApp.closeSurface(userdata, processAlive: processAlive)
            }
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

    // MARK: - Action Routing

    private nonisolated static func handleAction(
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

    private nonisolated static func readClipboard(
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

    private nonisolated static func writeClipboard(
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

    private nonisolated static func closeSurface(
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
