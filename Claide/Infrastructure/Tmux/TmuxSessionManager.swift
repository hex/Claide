// ABOUTME: Maps tmux panes/windows to Claide views and routes I/O between them.
// ABOUTME: Bridges TmuxControlChannel notifications to GhosttyTerminalView surfaces.

import AppKit
import Foundation

/// Coordinates tmux control mode panes with Claide terminal views.
///
/// Owns a `TmuxControlChannel` and maps tmux pane IDs to `GhosttyTerminalView`
/// instances. Decoded `%output` data is routed to the correct surface via
/// `feedOutput`. Keyboard input from tmux panes is intercepted and sent as
/// `send-keys` commands through the control channel.
@MainActor
final class TmuxSessionManager {

    /// Fired when a new tmux window should be created as a Claide tab.
    var onWindowAdd: ((Int, String?) -> Void)?

    /// Fired when a tmux window is closed.
    var onWindowClose: ((Int) -> Void)?

    /// Fired when a tmux window is renamed.
    var onWindowRenamed: ((Int, String) -> Void)?

    /// Fired when the tmux session disconnects.
    var onDisconnect: (() -> Void)?

    /// Fired when a command response block completes.
    var onCommandResponse: ((Int, Result<String, TmuxCommandError>) -> Void)?

    private let channel: TmuxControlChannel
    private var paneViews: [Int: GhosttyTerminalView] = [:]
    private var nextCommandNumber = 0

    init(channel: TmuxControlChannel) {
        self.channel = channel
        channel.onNotification = { [weak self] notification in
            DispatchQueue.main.async { [weak self] in
                self?.handle(notification)
            }
        }
        channel.onDisconnect = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.onDisconnect?()
            }
        }
    }

    // MARK: - Pane Registration

    /// Register a terminal view to receive output for a tmux pane.
    func register(view: GhosttyTerminalView, forPane paneID: Int) {
        paneViews[paneID] = view
    }

    /// Remove a pane's view registration.
    func unregister(pane paneID: Int) {
        paneViews.removeValue(forKey: paneID)
    }

    // MARK: - Input Interceptor

    /// Returns an input interceptor closure for a specific tmux pane.
    ///
    /// The closure converts NSEvents to tmux `send-keys` commands and sends
    /// them through the control channel. Returns `true` to consume the event.
    func inputInterceptor(forPane paneID: Int) -> (NSEvent) -> Bool {
        return { [weak self] event in
            guard let self else { return false }
            guard event.type == .keyDown else { return false }
            return self.sendKey(event: event, toPane: paneID)
        }
    }

    // MARK: - Commands

    /// Send a tmux command and get the response via onCommandResponse.
    func sendCommand(_ command: String) {
        channel.send(command: command)
    }

    /// Detach from the tmux session.
    func detach() {
        channel.detach()
    }

    /// Resize a tmux pane to the given dimensions.
    func resizePane(_ paneID: Int, columns: Int, rows: Int) {
        channel.send(command: "resize-pane -t %\(paneID) -x \(columns) -y \(rows)")
    }

    var isConnected: Bool {
        channel.isRunning
    }

    // MARK: - Notification Handling

    private func handle(_ notification: TmuxNotification) {
        switch notification {
        case .output(let paneID, let data):
            paneViews[paneID]?.feedOutput(data)

        case .windowAdd(let windowID):
            onWindowAdd?(windowID, nil)

        case .windowClose(let windowID):
            onWindowClose?(windowID)

        case .windowRenamed(let windowID, let name):
            onWindowRenamed?(windowID, name)

        case .blockEnd(let cmdNum, let data):
            onCommandResponse?(cmdNum, .success(data))

        case .blockError(let cmdNum, let data):
            onCommandResponse?(cmdNum, .failure(TmuxCommandError(message: data)))

        case .exit:
            onDisconnect?()

        case .layoutChange, .windowPaneChanged, .paneModeChanged,
             .sessionChanged, .sessionsChanged, .unrecognized:
            break
        }
    }

    // MARK: - Key Encoding

    private func sendKey(event: NSEvent, toPane paneID: Int) -> Bool {
        guard let keyNotation = tmuxKeyNotation(for: event) else { return false }
        channel.send(command: "send-keys -t %\(paneID) \(keyNotation)")
        return true
    }

    /// Convert an NSEvent to tmux key notation for send-keys.
    private func tmuxKeyNotation(for event: NSEvent) -> String? {
        // Special keys first
        if let special = tmuxSpecialKey(keyCode: event.keyCode) {
            return withModifierPrefix(event.modifierFlags, key: special)
        }

        // Printable characters
        guard let chars = event.characters, !chars.isEmpty else { return nil }

        // Control+letter combinations
        if event.modifierFlags.contains(.control) {
            if let scalar = chars.unicodeScalars.first, scalar.value < 0x20 {
                let letter = Character(UnicodeScalar(scalar.value + 0x40)!)
                return withModifierPrefix(
                    event.modifierFlags.subtracting(.control),
                    key: "C-\(letter)"
                )
            }
        }

        // Regular printable text — quote if it contains spaces or special chars
        let escaped = chars.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func tmuxSpecialKey(keyCode: UInt16) -> String? {
        switch keyCode {
        case 0x24: return "Enter"
        case 0x30: return "Tab"
        case 0x33: return "BSpace"
        case 0x35: return "Escape"
        case 0x7B: return "Left"
        case 0x7C: return "Right"
        case 0x7D: return "Down"
        case 0x7E: return "Up"
        case 0x73: return "Home"
        case 0x77: return "End"
        case 0x74: return "PageUp" // Page Up
        case 0x79: return "PageDown" // Page Down
        case 0x75: return "DC" // Forward Delete
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default: return nil
        }
    }

    private func withModifierPrefix(_ flags: NSEvent.ModifierFlags, key: String) -> String {
        var prefixes: [String] = []
        if flags.contains(.shift)   { prefixes.append("S-") }
        if flags.contains(.option)  { prefixes.append("M-") }
        // Note: .control is handled inline for C-<letter> notation
        if prefixes.isEmpty { return key }
        return prefixes.joined() + key
    }
}

struct TmuxCommandError: Error {
    let message: String
}
