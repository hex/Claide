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
    /// Parameters: (windowID, paneID, name)
    var onWindowAdd: ((Int, Int, String?) -> Void)?

    /// Fired when a tmux window is closed.
    var onWindowClose: ((Int) -> Void)?

    /// Fired when a tmux window is renamed.
    var onWindowRenamed: ((Int, String) -> Void)?

    /// Fired when the tmux session disconnects.
    var onDisconnect: (() -> Void)?

    private let channel: TmuxControlChannel
    private var paneViews: [Int: GhosttyTerminalView] = [:]
    private var nextCommandNumber = 0
    private var commandHandlers: [Int: (Result<String, TmuxCommandError>) -> Void] = [:]

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

    /// Send a tmux command. Fire-and-forget (no response handler).
    func sendCommand(_ command: String) {
        nextCommandNumber += 1
        channel.send(command: command)
    }

    /// Send a tmux command and receive the `%begin/%end` response.
    ///
    /// The handler is called with the block response when the matching
    /// `%end` or `%error` notification arrives.
    func sendCommand(_ command: String, handler: @escaping (Result<String, TmuxCommandError>) -> Void) {
        let cmdNum = nextCommandNumber
        nextCommandNumber += 1
        commandHandlers[cmdNum] = handler
        channel.send(command: command)
    }

    /// Detach from the tmux session.
    func detach() {
        channel.detach()
    }

    /// Resize a tmux pane to the given dimensions.
    func resizePane(_ paneID: Int, columns: Int, rows: Int) {
        sendCommand("resize-pane -t %\(paneID) -x \(columns) -y \(rows)")
    }

    var isConnected: Bool {
        channel.isRunning
    }

    // MARK: - Window Enumeration

    /// Query tmux for all existing windows and create tabs for each.
    ///
    /// Sends `list-panes -s` to enumerate all panes in the session.
    /// Calls `onWindowAdd` for each window found.
    func enumerateWindows() {
        let format = "#{window_id}\t#{pane_id}\t#{window_name}"
        sendCommand("list-panes -s -F '\(format)'") { [weak self] result in
            guard let self else { return }
            if case .success(let data) = result {
                let windows = Self.parseWindowList(data)
                for window in windows {
                    self.onWindowAdd?(window.windowID, window.paneID, window.name)
                }
            }
        }
    }

    // MARK: - Notification Handling

    private func handle(_ notification: TmuxNotification) {
        switch notification {
        case .output(let paneID, let data):
            paneViews[paneID]?.feedOutput(data)

        case .windowAdd(let windowID):
            resolveWindowPane(windowID: windowID)

        case .windowClose(let windowID):
            onWindowClose?(windowID)

        case .windowRenamed(let windowID, let name):
            onWindowRenamed?(windowID, name)

        case .blockEnd(let cmdNum, let data):
            if let handler = commandHandlers.removeValue(forKey: cmdNum) {
                handler(.success(data))
            }

        case .blockError(let cmdNum, let data):
            if let handler = commandHandlers.removeValue(forKey: cmdNum) {
                handler(.failure(TmuxCommandError(message: data)))
            }

        case .exit:
            onDisconnect?()

        case .layoutChange, .windowPaneChanged, .paneModeChanged,
             .sessionChanged, .sessionsChanged, .unrecognized:
            break
        }
    }

    /// Query tmux for the active pane in a newly added window.
    private func resolveWindowPane(windowID: Int) {
        sendCommand("list-panes -t @\(windowID) -F '#{pane_id} #{window_name}'") { [weak self] result in
            guard let self else { return }
            if case .success(let data) = result {
                let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                if let first = parts.first, first.hasPrefix("%"), let paneID = Int(first.dropFirst()) {
                    let name = parts.count > 1 ? String(parts[1]) : nil
                    self.onWindowAdd?(windowID, paneID, name)
                }
            }
        }
    }

    // MARK: - Window List Parsing

    /// Parsed tmux window information from `list-panes` output.
    struct WindowInfo {
        let windowID: Int
        let paneID: Int
        let name: String
    }

    /// Parse tab-separated `list-panes -s` output into window info structs.
    ///
    /// Expected format per line: `@<windowID>\t%<paneID>\t<name>`
    /// Lines that don't match the expected format are skipped.
    nonisolated static func parseWindowList(_ response: String) -> [WindowInfo] {
        response.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count >= 2,
                  parts[0].hasPrefix("@"), let windowID = Int(parts[0].dropFirst()),
                  parts[1].hasPrefix("%"), let paneID = Int(parts[1].dropFirst())
            else { return nil }
            let name = parts.count > 2 ? String(parts[2]) : ""
            return WindowInfo(windowID: windowID, paneID: paneID, name: name)
        }
    }

    /// Parse a single pane ID from `list-panes -t @N` output.
    ///
    /// Expects a line like `%5` (possibly with trailing whitespace/newline).
    nonisolated static func parsePaneID(_ response: String) -> Int? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("%"), let id = Int(trimmed.dropFirst()) else { return nil }
        return id
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
