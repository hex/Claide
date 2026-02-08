// ABOUTME: Represents a single file operation from transcript, git, or filesystem.
// ABOUTME: Parses JSONL transcripts, git status output, and changes.md log lines.

import Foundation

enum ChangeSource: Sendable, Equatable {
    case transcript
    case git
}

struct FileChange: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let tool: String
    let filePath: String
    let source: ChangeSource

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
        return FileChange(timestamp: date, tool: tool, filePath: path, source: .transcript)
    }

    /// Parse all lines from a changes.md file contents
    static func parseAll(from contents: String) -> [FileChange] {
        contents
            .components(separatedBy: .newlines)
            .compactMap { parse(line: $0) }
    }

    // MARK: - Git Status Parsing

    private static let gitStatusMap: [Character: String] = [
        "M": "Modified",
        "A": "Added",
        "D": "Deleted",
        "?": "Untracked",
        "R": "Renamed",
        "C": "Copied",
        "U": "Conflict",
    ]

    /// Parse `git status --porcelain` output into file changes.
    /// The repoRoot is prepended to relative paths to form absolute paths.
    static func parseGitStatus(_ output: String, repoRoot: String) -> [FileChange] {
        let root = repoRoot.hasSuffix("/") ? repoRoot : repoRoot + "/"
        let now = Date()

        return output
            .components(separatedBy: "\n")
            .compactMap { line -> FileChange? in
                // Only strip trailing whitespace — the leading chars are status columns
                var cleaned = line
                while cleaned.last?.isWhitespace == true { cleaned.removeLast() }
                guard cleaned.count >= 4 else { return nil }

                // Porcelain format: XY <space> path
                // X = index status, Y = working tree status
                let chars = Array(cleaned)
                let indexStatus = chars[0]
                let workTreeStatus = chars[1]

                // Pick the most relevant status: working tree first, then index
                let statusChar: Character
                if workTreeStatus != " " && workTreeStatus != "?" {
                    statusChar = workTreeStatus
                } else if indexStatus != " " && indexStatus != "?" {
                    statusChar = indexStatus
                } else if indexStatus == "?" {
                    statusChar = "?"
                } else {
                    return nil
                }

                guard let tool = gitStatusMap[statusChar] else { return nil }

                // Path starts after "XY "
                let pathStart = cleaned.index(cleaned.startIndex, offsetBy: 3)
                let relativePath = String(cleaned[pathStart...])
                let absolutePath = root + relativePath

                // Use file's actual modification date when available
                let modDate: Date
                if let attrs = try? FileManager.default.attributesOfItem(atPath: absolutePath),
                   let date = attrs[.modificationDate] as? Date {
                    modDate = date
                } else {
                    modDate = now
                }

                return FileChange(
                    timestamp: modDate,
                    tool: tool,
                    filePath: absolutePath,
                    source: .git
                )
            }
    }

    // MARK: - Transcript Parsing

    private static let fileTools: Set<String> = ["Write", "Edit", "MultiEdit", "Read"]

    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Extract file operations from a Claude Code JSONL transcript.
    /// Returns changes in chronological order.
    static func parseTranscript(_ data: Data) -> [FileChange] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var results: [FileChange] = []
        let decoder = JSONDecoder()

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let entry = try? decoder.decode(TranscriptEntry.self, from: lineData),
                  entry.type == "assistant",
                  let contents = entry.message?.content else {
                continue
            }

            let timestamp = entry.timestamp
                .flatMap { iso8601Formatter.date(from: $0) }
                ?? Date.distantPast

            for item in contents {
                guard item.type == "tool_use",
                      let name = item.name,
                      fileTools.contains(name),
                      let path = item.input?.filePath else {
                    continue
                }
                results.append(FileChange(timestamp: timestamp, tool: name, filePath: path, source: .transcript))
            }
        }

        return results
    }
}
