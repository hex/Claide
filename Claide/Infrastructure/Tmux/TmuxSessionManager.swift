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

    /// Fired when a new pane appears in an existing window (from split-window).
    /// Parameters: (windowID, paneID)
    var onPaneAdd: ((Int, Int) -> Void)?

    /// Fired when a pane is removed from a window.
    /// Parameters: (windowID, paneID)
    var onPaneRemove: ((Int, Int) -> Void)?

    /// Fired when the tmux session disconnects.
    var onDisconnect: (() -> Void)?

    private let channel: TmuxControlChannel
    private var paneViews: [Int: GhosttyTerminalView] = [:]
    /// FIFO queue of response handlers. tmux command numbers are global server
    /// counters that we can't predict, but responses arrive in send order.
    private var pendingHandlers: [(Result<String, TmuxCommandError>) -> Void] = []

    /// Tracks known pane IDs per window for diffing on layout change.
    private var windowPanes: [Int: Set<Int>] = [:]

    /// Buffers %output data for panes whose views haven't been registered yet.
    /// Replayed in order when the view is registered via `register(view:forPane:)`.
    private var pendingOutput: [Int: [Data]] = [:]

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

    /// Erase display + cursor home.
    private static let clearSequence = Data("\u{1b}[2J\u{1b}[H".utf8)

    /// Register a terminal view to receive output for a tmux pane.
    ///
    /// Replays any buffered `%output` data that arrived before the view
    /// was created (tmux sends initial pane content immediately on attach).
    ///
    /// The replay is delayed 300ms so login(1)'s "Last login" message
    /// (which arrives on the PTY thread) has time to finish before we
    /// clear it via feedOutput on the main thread.
    func register(view: GhosttyTerminalView, forPane paneID: Int) {
        paneViews[paneID] = view
        let buffered = pendingOutput.removeValue(forKey: paneID)

        // Delay clear + replay so login(1)'s "Last login" message (on the
        // PTY thread) finishes before we overwrite it via feedOutput.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak view] in
            guard let view else { return }
            view.feedOutput(Self.clearSequence)
            if let buffered {
                for data in buffered {
                    view.feedOutput(data)
                }
            }
        }
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
        channel.send(command: command)
    }

    /// Send a tmux command and receive the `%begin/%end` response.
    ///
    /// The handler is called with the block response when the matching
    /// `%end` or `%error` notification arrives. Handlers are dequeued in
    /// FIFO order since tmux responses arrive in command send order.
    func sendCommand(_ command: String, handler: @escaping (Result<String, TmuxCommandError>) -> Void) {
        pendingHandlers.append(handler)
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
                // Group panes by window for initial tracking
                var grouped: [Int: [WindowInfo]] = [:]
                for window in windows {
                    grouped[window.windowID, default: []].append(window)
                }
                for (windowID, panes) in grouped {
                    self.windowPanes[windowID] = Set(panes.map(\.paneID))
                }
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
            if let view = paneViews[paneID] {
                view.feedOutput(data)
            } else {
                pendingOutput[paneID, default: []].append(data)
            }

        case .windowAdd(let windowID):
            resolveWindowPane(windowID: windowID)

        case .windowClose(let windowID):
            windowPanes.removeValue(forKey: windowID)
            onWindowClose?(windowID)

        case .windowRenamed(let windowID, let name):
            onWindowRenamed?(windowID, name)

        case .blockEnd(_, let data):
            if !pendingHandlers.isEmpty {
                let handler = pendingHandlers.removeFirst()
                handler(.success(data))
            }

        case .blockError(_, let data):
            if !pendingHandlers.isEmpty {
                let handler = pendingHandlers.removeFirst()
                handler(.failure(TmuxCommandError(message: data)))
            }

        case .exit:
            onDisconnect?()

        case .layoutChange(let windowID, let layout):
            handleLayoutChange(windowID: windowID, layout: layout)

        case .windowPaneChanged, .paneModeChanged,
             .sessionChanged, .sessionsChanged, .unrecognized:
            break
        }
    }

    /// Diff pane sets when a window's layout changes.
    ///
    /// Parses the tmux layout descriptor, compares against known panes,
    /// and fires `onPaneAdd` / `onPaneRemove` for the differences.
    private func handleLayoutChange(windowID: Int, layout: String) {
        guard let node = TmuxLayoutParser.parse(layout) else { return }
        let newPanes = Set(node.allPaneIDs)
        let oldPanes = windowPanes[windowID] ?? []

        let added = newPanes.subtracting(oldPanes)
        let removed = oldPanes.subtracting(newPanes)

        windowPanes[windowID] = newPanes

        for paneID in added {
            onPaneAdd?(windowID, paneID)
        }
        for paneID in removed {
            paneViews.removeValue(forKey: paneID)
            onPaneRemove?(windowID, paneID)
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

    // MARK: - Session List Parsing

    /// Parsed tmux session information from `list-sessions` output.
    struct SessionInfo {
        let name: String
        let windowCount: Int
        let isAttached: Bool
    }

    /// Parse `tmux list-sessions` output into session info structs.
    ///
    /// Expected format per line: `<name>: N windows (created ...) [(attached)]`
    /// The name may contain colons, so we match the `: N windows` pattern from the right.
    nonisolated static func parseSessionList(_ response: String) -> [SessionInfo] {
        response.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            // Match ": N windows" to split name from the rest.
            guard let range = trimmed.range(of: #": (\d+) windows?"#, options: .regularExpression) else {
                return nil
            }

            let name = String(trimmed[trimmed.startIndex..<range.lowerBound])
            let afterColon = trimmed[range]
            // Extract window count from ": N windows"
            let digits = afterColon.drop(while: { !$0.isNumber })
            let windowCount = Int(digits.prefix(while: { $0.isNumber })) ?? 0
            let isAttached = trimmed.hasSuffix("(attached)")

            return SessionInfo(name: name, windowCount: windowCount, isAttached: isAttached)
        }
    }

    /// List available tmux sessions by running `tmux list-sessions` synchronously.
    ///
    /// Returns an empty array if tmux is not installed or no sessions exist.
    nonisolated static func listSessions() -> [SessionInfo] {
        guard let tmuxPath = findTmux() else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = ["list-sessions"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return parseSessionList(output)
    }

    // MARK: - Resize Handler

    /// Returns a resize handler closure for a specific tmux pane.
    ///
    /// The closure debounces resize events and sends `resize-pane` commands.
    func resizeHandler(forPane paneID: Int) -> (Int, Int) -> Void {
        var resizeTask: DispatchWorkItem?
        return { [weak self] columns, rows in
            resizeTask?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.resizePane(paneID, columns: columns, rows: rows)
            }
            resizeTask = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
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
