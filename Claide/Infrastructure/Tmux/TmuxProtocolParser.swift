// ABOUTME: Stateful line parser for tmux control mode protocol.
// ABOUTME: Converts raw stdout lines into typed TmuxNotification values.

import Foundation

/// Parses lines from tmux control mode (-CC) stdout into typed notifications.
///
/// Tmux control mode sends `%`-prefixed notifications on stdout. Multi-line
/// command responses are bracketed by `%begin` / `%end` (or `%error`).
/// The parser accumulates block lines and emits a single notification when
/// the block closes.
final class TmuxProtocolParser {

    /// Callback invoked for each parsed notification.
    var onNotification: ((TmuxNotification) -> Void)?

    // Block accumulation state.
    private var activeBlock: BlockState?

    private struct BlockState {
        let commandNumber: Int
        var lines: [String]
    }

    /// Feed a single line (without trailing newline) to the parser.
    func feed(line rawLine: String) {
        let line = rawLine.hasSuffix("\r")
            ? String(rawLine.dropLast())
            : rawLine

        guard !line.isEmpty else { return }

        // Notifications always start with %.
        // Lines that don't start with % are either block content or ignored.
        if line.hasPrefix("%") {
            if let result = tryParseNotification(line) {
                if let notification = result {
                    onNotification?(notification)
                }
                // Recognized notification type (even if it didn't emit,
                // e.g. %begin opens a block but doesn't emit). Don't accumulate.
                return
            }
        }

        // If we're inside a block, accumulate the line.
        if activeBlock != nil {
            activeBlock!.lines.append(line)
        }
        // Lines outside a block that aren't notifications are ignored.
    }

    // MARK: - Notification dispatch

    /// Returns `.some(notification)` for recognized types, `nil` if the line
    /// is not a known notification type (should be accumulated in a block).
    /// `.some(nil)` means recognized but no notification emitted (e.g. %begin).
    private func tryParseNotification(_ line: String) -> TmuxNotification?? {
        // Split off the notification type (first word including %).
        let spaceIndex = line.firstIndex(of: " ")
        let type = spaceIndex.map { String(line[line.startIndex..<$0]) } ?? line
        let rest = spaceIndex.map { String(line[line.index(after: $0)...]) } ?? ""

        switch type {
        case "%output":
            return .some(parseOutput(rest))
        case "%begin":
            parseBegin(rest)
            return .some(nil)
        case "%end":
            return .some(parseEnd(rest, isError: false))
        case "%error":
            return .some(parseEnd(rest, isError: true))
        case "%window-add":
            return .some(parseWindowID(rest).map { .windowAdd(windowID: $0) })
        case "%window-close":
            return .some(parseWindowID(rest).map { .windowClose(windowID: $0) })
        case "%window-renamed":
            return .some(parseWindowRenamed(rest))
        case "%layout-change":
            return .some(parseLayoutChange(rest))
        case "%window-pane-changed":
            return .some(parseWindowPaneChanged(rest))
        case "%pane-mode-changed":
            return .some(parsePaneID(rest).map { .paneModeChanged(paneID: $0) })
        case "%session-changed":
            return .some(parseSessionChanged(rest))
        case "%sessions-changed":
            return .some(.sessionsChanged)
        case "%exit":
            return .some(.exit(reason: rest.isEmpty ? nil : rest))
        default:
            return .some(.unrecognized(line: line))
        }
    }

    // MARK: - %output

    private func parseOutput(_ rest: String) -> TmuxNotification? {
        // Format: %<pane_id> <octal-escaped-data>
        guard let spaceIdx = rest.firstIndex(of: " ") else { return nil }
        let paneStr = String(rest[rest.startIndex..<spaceIdx])
        guard let paneID = parsePaneID(paneStr) else { return nil }

        let dataStr = String(rest[rest.index(after: spaceIdx)...])
        let data = Self.octalUnescape(dataStr)
        return .output(paneID: paneID, data: data)
    }

    // MARK: - %begin / %end / %error

    private func parseBegin(_ rest: String) {
        // Format: <time> <cmd-number> <flags>
        let parts = rest.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let cmdNum = Int(parts[1]) else { return }
        activeBlock = BlockState(commandNumber: cmdNum, lines: [])
    }

    private func parseEnd(_ rest: String, isError: Bool) -> TmuxNotification? {
        guard let block = activeBlock else { return nil }
        activeBlock = nil
        let data = block.lines.joined(separator: "\n")
        if isError {
            return .blockError(commandNumber: block.commandNumber, data: data)
        } else {
            return .blockEnd(commandNumber: block.commandNumber, data: data)
        }
    }

    // MARK: - Window / pane / session ID parsing

    /// Parse `@<n>` into an Int.
    private func parseWindowID(_ str: String) -> Int? {
        guard str.hasPrefix("@"), let n = Int(str.dropFirst()) else { return nil }
        return n
    }

    /// Parse `%<n>` into an Int.
    private func parsePaneID(_ str: String) -> Int? {
        guard str.hasPrefix("%"), let n = Int(str.dropFirst()) else { return nil }
        return n
    }

    /// Parse `$<n>` into an Int.
    private func parseSessionID(_ str: String) -> Int? {
        guard str.hasPrefix("$"), let n = Int(str.dropFirst()) else { return nil }
        return n
    }

    // MARK: - Compound notification parsers

    private func parseWindowRenamed(_ rest: String) -> TmuxNotification? {
        // Format: @<window_id> <name>
        guard let spaceIdx = rest.firstIndex(of: " ") else { return nil }
        let windowStr = String(rest[rest.startIndex..<spaceIdx])
        guard let windowID = parseWindowID(windowStr) else { return nil }
        let name = String(rest[rest.index(after: spaceIdx)...])
        return .windowRenamed(windowID: windowID, name: name)
    }

    private func parseLayoutChange(_ rest: String) -> TmuxNotification? {
        // Format: @<window_id> <layout-descriptor>
        guard let spaceIdx = rest.firstIndex(of: " ") else { return nil }
        let windowStr = String(rest[rest.startIndex..<spaceIdx])
        guard let windowID = parseWindowID(windowStr) else { return nil }
        let layout = String(rest[rest.index(after: spaceIdx)...])
        return .layoutChange(windowID: windowID, layout: layout)
    }

    private func parseWindowPaneChanged(_ rest: String) -> TmuxNotification? {
        // Format: @<window_id> %<pane_id>
        let parts = rest.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        guard let windowID = parseWindowID(String(parts[0])) else { return nil }
        guard let paneID = parsePaneID(String(parts[1])) else { return nil }
        return .windowPaneChanged(windowID: windowID, paneID: paneID)
    }

    private func parseSessionChanged(_ rest: String) -> TmuxNotification? {
        // Format: $<session_id> <session_name>
        guard let spaceIdx = rest.firstIndex(of: " ") else { return nil }
        let sessionStr = String(rest[rest.startIndex..<spaceIdx])
        guard let sessionID = parseSessionID(sessionStr) else { return nil }
        let name = String(rest[rest.index(after: spaceIdx)...])
        return .sessionChanged(sessionID: sessionID, name: name)
    }

    // MARK: - Octal unescape

    /// Decode tmux octal-escaped string into raw bytes.
    ///
    /// tmux escapes bytes as `\ooo` (exactly 3 octal digits).
    /// A backslash NOT followed by 3 octal digits is treated as a literal backslash.
    static func octalUnescape(_ string: String) -> Data {
        var result = Data()
        let chars = Array(string.utf8)
        var i = 0

        while i < chars.count {
            if chars[i] == UInt8(ascii: "\\") && i + 3 < chars.count {
                let d0 = chars[i + 1]
                let d1 = chars[i + 2]
                let d2 = chars[i + 3]
                if isOctalDigit(d0) && isOctalDigit(d1) && isOctalDigit(d2) {
                    let value = (UInt8(d0) - 0x30) * 64
                        + (UInt8(d1) - 0x30) * 8
                        + (UInt8(d2) - 0x30)
                    result.append(value)
                    i += 4
                    continue
                }
            }
            result.append(chars[i])
            i += 1
        }

        return result
    }

    private static func isOctalDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "7")
    }
}
