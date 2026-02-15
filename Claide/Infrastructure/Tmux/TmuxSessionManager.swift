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

    // MARK: - Paste Handler

    /// Returns a paste handler closure for a specific tmux pane.
    ///
    /// The closure sends pasted text as literal keys via `send-keys -l`.
    func pasteHandler(forPane paneID: Int) -> (String) -> Void {
        return { [weak self] text in
            guard let self, !text.isEmpty else { return }
            let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
            self.channel.send(command: "send-keys -t %\(paneID) -l '\(escaped)'")
        }
    }

    // MARK: - Key Encoding

    private func sendKey(event: NSEvent, toPane paneID: Int) -> Bool {
        guard let keyNotation = TmuxKeyEncoder.encode(event) else { return false }
        channel.send(command: "send-keys -t %\(paneID) \(keyNotation)")
        return true
    }
}

struct TmuxCommandError: Error {
    let message: String
}
