// ABOUTME: Represents a single file modification parsed from changes.md.
// ABOUTME: Extracts timestamp, tool name, and file path from each log line.

import Foundation

struct FileChange: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let tool: String
    let filePath: String

    /// The filename component for display
    var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    /// The parent directory for context
    var directory: String {
        (filePath as NSString).deletingLastPathComponent
    }

    // Format: "- [2026-01-31 23:33:01] Write: /path/to/file"
    private nonisolated(unsafe) static let linePattern = /^- \[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (\w+): (.+)$/

    private nonisolated(unsafe) static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Parse a single line from changes.md. Returns nil if format doesn't match.
    static func parse(line: String) -> FileChange? {
        guard let match = line.firstMatch(of: linePattern) else { return nil }
        let dateStr = String(match.1)
        let tool = String(match.2)
        let path = String(match.3)
        guard let date = dateFormatter.date(from: dateStr) else { return nil }
        return FileChange(timestamp: date, tool: tool, filePath: path)
    }

    /// Parse all lines from a changes.md file contents
    static func parseAll(from contents: String) -> [FileChange] {
        contents
            .components(separatedBy: .newlines)
            .compactMap { parse(line: $0) }
    }
}
