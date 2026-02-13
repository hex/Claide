// ABOUTME: Singleton owning the Ghostty terminal engine (ghostty_app_t).
// ABOUTME: Creates config, registers runtime callbacks, and routes actions to surfaces.

import AppKit
import os

@MainActor
final class GhosttyApp {

    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.hexul.claide", category: "ghostty")

    private init() {}

    // MARK: - Lifecycle

    /// Initialize the Ghostty engine with the given configuration overrides.
    func start(fontFamily: String = "", fontSize: Float = 0, colorScheme: TerminalColorScheme? = nil) {
        guard app == nil else { return }

        guard let config = ghostty_config_new() else {
            logger.error("ghostty_config_new failed")
            return
        }

        // Write a temp config file with our settings, then load it.
        // Ghostty config is file-based — there's no programmatic setter API.
        let configPath = writeConfigFile(
            fontFamily: fontFamily,
            fontSize: fontSize,
            colorScheme: colorScheme
        )
        if let path = configPath {
            path.withCString { cPath in
                ghostty_config_load_file(config, cPath)
            }
        }

        ghostty_config_finalize(config)

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
            write_clipboard_cb: { userdata, location, content, count, confirm in
                GhosttyApp.writeClipboard(userdata, location: location, content: content, count: count, confirm: confirm)
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

    // MARK: - Config File

    /// Writes Ghostty config to a temporary file and returns the path.
    private func writeConfigFile(
        fontFamily: String,
        fontSize: Float,
        colorScheme: TerminalColorScheme?
    ) -> String? {
        var lines: [String] = []

        // Disable Ghostty's built-in keybindings so Claide controls all shortcuts
        lines.append("keybind = clear")

        // Terminal identification
        lines.append("term = xterm-256color")

        // Disable features we handle ourselves
        lines.append("confirm-close-surface = false")
        lines.append("quit-after-last-window-closed = false")
        lines.append("window-decoration = false")

        // Font
        if !fontFamily.isEmpty {
            lines.append("font-family = \(fontFamily)")
        }
        if fontSize > 0 {
            lines.append("font-size = \(fontSize)")
        }

        // Colors
        if let scheme = colorScheme {
            lines.append("background = \(scheme.background.hexString)")
            lines.append("foreground = \(scheme.foreground.hexString)")
            for (i, color) in scheme.ansi.enumerated() {
                lines.append("palette = \(i)=\(color.hexString)")
            }
        }

        let content = lines.joined(separator: "\n") + "\n"
        let tempDir = FileManager.default.temporaryDirectory
        let configFile = tempDir.appendingPathComponent("claide-ghostty.conf")
        do {
            try content.write(to: configFile, atomically: true, encoding: .utf8)
            return configFile.path
        } catch {
            logger.error("Failed to write Ghostty config: \(error)")
            return nil
        }
    }

    // MARK: - Action Routing

    private static func handleAction(
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
                if let title { view.onTitle?(title) }
                return true

            case GHOSTTY_ACTION_RING_BELL:
                view.onBell?()
                return true

            case GHOSTTY_ACTION_MOUSE_SHAPE:
                view.updateMouseCursor(action.action.mouse_shape)
                return true

            case GHOSTTY_ACTION_RENDER:
                // Ghostty handles rendering internally
                return true

            case GHOSTTY_ACTION_CLOSE_SURFACE:
                view.onChildExit?(0)
                return true

            case GHOSTTY_ACTION_COLOR_CHANGE:
                // Terminal-initiated color change (e.g. OSC 10/11)
                return true

            default:
                return false
            }
        }

        // App-level actions
        switch action.tag {
        case GHOSTTY_ACTION_QUIT:
            return true  // We handle quit ourselves

        case GHOSTTY_ACTION_NEW_WINDOW, GHOSTTY_ACTION_NEW_TAB, GHOSTTY_ACTION_NEW_SPLIT:
            return true  // We handle window/tab/split management ourselves

        default:
            return false
        }
    }

    // MARK: - Clipboard

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        guard let state else { return }
        let pasteboard = NSPasteboard.general
        guard let content = pasteboard.string(forType: .string) else {
            // The clipboard request API takes (surface_t, string, state, confirmed)
            // state is an opaque pointer from Ghostty that we pass back
            ghostty_surface_complete_clipboard_request(state, nil, nil, true)
            return
        }
        content.withCString { ptr in
            ghostty_surface_complete_clipboard_request(state, ptr, nil, true)
        }
    }

    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        count: Int,
        confirm: Bool
    ) {
        guard let content, count > 0 else { return }
        let item = content.pointee
        if let data = item.data {
            let text = String(cString: data)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    private static func closeSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        // Surface close is handled via the action callback
    }
}
