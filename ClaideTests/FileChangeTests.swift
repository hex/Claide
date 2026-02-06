// ABOUTME: Tests for parsing file changes from changes.md and JSONL transcripts.
// ABOUTME: Validates timestamp extraction, tool types, and path handling.

import Testing
import Foundation
@testable import Claide

@Suite("File Change Parsing")
struct FileChangeTests {

    @Test("Parses valid change lines")
    func parsesValidLines() {
        let changes = FileChange.parseAll(from: Fixtures.changesMarkdown)
        #expect(changes.count == 3)
    }

    @Test("Extracts tool name correctly")
    func extractsToolName() {
        let changes = FileChange.parseAll(from: Fixtures.changesMarkdown)
        #expect(changes[0].tool == "Write")
        #expect(changes[1].tool == "Edit")
    }

    @Test("Extracts file path correctly")
    func extractsFilePath() {
        let changes = FileChange.parseAll(from: Fixtures.changesMarkdown)
        #expect(changes[0].filePath == "/Users/hex/project/src/main.swift")
    }

    @Test("Computes filename from path")
    func computesFilename() {
        let changes = FileChange.parseAll(from: Fixtures.changesMarkdown)
        #expect(changes[0].fileName == "main.swift")
        #expect(changes[2].fileName == "README.md")
    }

    @Test("Computes directory from path")
    func computesDirectory() {
        let changes = FileChange.parseAll(from: Fixtures.changesMarkdown)
        #expect(changes[0].directory == "/Users/hex/project/src")
    }

    @Test("Skips non-matching lines")
    func skipsNonMatchingLines() {
        let input = """
        # Header
        Some text

        - [2026-01-31 23:33:01] Write: /path/to/file
        """
        let changes = FileChange.parseAll(from: input)
        #expect(changes.count == 1)
    }

    @Test("Handles empty input")
    func handlesEmptyInput() {
        let changes = FileChange.parseAll(from: "")
        #expect(changes.isEmpty)
    }

    @Test("Parses timestamp correctly")
    func parsesTimestamp() {
        let changes = FileChange.parseAll(from: Fixtures.changesMarkdown)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: changes[0].timestamp)
        #expect(components.hour == 23)
        #expect(components.minute == 33)
        #expect(components.second == 1)
    }
}

// MARK: - Transcript Parsing

@Suite("Transcript Parsing")
struct TranscriptParsingTests {

    @Test("Parses Write entry from transcript")
    func parsesWriteEntry() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        let writes = changes.filter { $0.tool == "Write" }
        #expect(writes.count == 1)
        #expect(writes[0].filePath == "/Users/hex/project/src/main.swift")
    }

    @Test("Parses Edit entry from transcript")
    func parsesEditEntry() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        let edits = changes.filter { $0.tool == "Edit" }
        #expect(edits.count == 1)
        #expect(edits[0].filePath == "/Users/hex/project/src/utils.swift")
    }

    @Test("Parses Read entry from transcript")
    func parsesReadEntry() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        let reads = changes.filter { $0.tool == "Read" }
        #expect(reads.count == 1)
        #expect(reads[0].filePath == "/Users/hex/project/README.md")
    }

    @Test("Parses MultiEdit entry from transcript")
    func parsesMultiEditEntry() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        let multiEdits = changes.filter { $0.tool == "MultiEdit" }
        #expect(multiEdits.count == 1)
        #expect(multiEdits[0].filePath == "/Users/hex/project/src/views.swift")
    }

    @Test("Skips text-only content blocks")
    func skipsTextContent() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        // Only Write, Edit, Read, MultiEdit should be present (4 total)
        #expect(changes.count == 4)
    }

    @Test("Skips tool_use without file_path (Bash, Grep, etc)")
    func skipsToolsWithoutFilePath() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        let bash = changes.filter { $0.tool == "Bash" }
        #expect(bash.isEmpty)
    }

    @Test("Skips non-assistant entries")
    func skipsUserEntries() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        // No user-originated tools should appear
        #expect(changes.allSatisfy { ["Write", "Edit", "Read", "MultiEdit"].contains($0.tool) })
    }

    @Test("Handles malformed JSON lines gracefully")
    func handlesMalformedLines() {
        let data = """
        not json at all
        {"type":"assistant","timestamp":"2026-02-06T10:30:01.000Z","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/path/to/file"}}]}}
        {incomplete json
        """.data(using: .utf8)!
        let changes = FileChange.parseTranscript(data)
        #expect(changes.count == 1)
        #expect(changes[0].filePath == "/path/to/file")
    }

    @Test("Empty data returns empty array")
    func emptyDataReturnsEmpty() {
        let changes = FileChange.parseTranscript(Data())
        #expect(changes.isEmpty)
    }

    @Test("Preserves chronological order")
    func preservesChronologicalOrder() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        #expect(changes.count == 4)
        #expect(changes[0].tool == "Write")
        #expect(changes[1].tool == "Edit")
        #expect(changes[2].tool == "Read")
        #expect(changes[3].tool == "MultiEdit")
    }

    @Test("Parses ISO 8601 timestamp correctly")
    func parsesTimestamp() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let components = utc.dateComponents([.hour, .minute, .second], from: changes[0].timestamp)
        #expect(components.hour == 10)
        #expect(components.minute == 30)
        #expect(components.second == 1)
    }
}

// MARK: - Git Status Parsing

@Suite("Git Status Parsing")
struct GitStatusParsingTests {

    let repoRoot = "/Users/hex/project"

    @Test("Parses modified file from working tree")
    func parsesModifiedFile() {
        let changes = FileChange.parseGitStatus(Fixtures.gitStatusPorcelain, repoRoot: repoRoot)
        let modified = changes.filter { $0.filePath.hasSuffix("main.swift") }
        #expect(modified.count == 1)
        #expect(modified[0].tool == "Modified")
        #expect(modified[0].filePath == "/Users/hex/project/src/main.swift")
        #expect(modified[0].source == .git)
    }

    @Test("Parses staged modified file")
    func parsesStagedFile() {
        let changes = FileChange.parseGitStatus(Fixtures.gitStatusPorcelain, repoRoot: repoRoot)
        let staged = changes.filter { $0.filePath.hasSuffix("staged.swift") }
        #expect(staged.count == 1)
        #expect(staged[0].tool == "Modified")
    }

    @Test("Parses added file")
    func parsesAddedFile() {
        let changes = FileChange.parseGitStatus(Fixtures.gitStatusPorcelain, repoRoot: repoRoot)
        let added = changes.filter { $0.filePath.hasSuffix("new.swift") }
        #expect(added.count == 1)
        #expect(added[0].tool == "Added")
    }

    @Test("Parses untracked file")
    func parsesUntrackedFile() {
        let changes = FileChange.parseGitStatus(Fixtures.gitStatusPorcelain, repoRoot: repoRoot)
        let untracked = changes.filter { $0.filePath.hasSuffix("untracked.txt") }
        #expect(untracked.count == 1)
        #expect(untracked[0].tool == "Untracked")
    }

    @Test("Parses deleted file")
    func parsesDeletedFile() {
        let changes = FileChange.parseGitStatus(Fixtures.gitStatusPorcelain, repoRoot: repoRoot)
        let deleted = changes.filter { $0.filePath.hasSuffix("deleted.swift") }
        #expect(deleted.count == 1)
        #expect(deleted[0].tool == "Deleted")
    }

    @Test("Parses file modified in both index and working tree")
    func parsesBothModified() {
        let changes = FileChange.parseGitStatus(Fixtures.gitStatusPorcelain, repoRoot: repoRoot)
        let both = changes.filter { $0.filePath.hasSuffix("both.swift") }
        #expect(both.count == 1)
        #expect(both[0].tool == "Modified")
    }

    @Test("Builds absolute paths from repo root")
    func buildsAbsolutePaths() {
        let changes = FileChange.parseGitStatus(Fixtures.gitStatusPorcelain, repoRoot: repoRoot)
        #expect(changes.allSatisfy { $0.filePath.hasPrefix("/Users/hex/project/") })
    }

    @Test("All git entries have .git source")
    func allGitSource() {
        let changes = FileChange.parseGitStatus(Fixtures.gitStatusPorcelain, repoRoot: repoRoot)
        #expect(changes.allSatisfy { $0.source == .git })
    }

    @Test("Parses correct total count")
    func parsesCorrectCount() {
        let changes = FileChange.parseGitStatus(Fixtures.gitStatusPorcelain, repoRoot: repoRoot)
        #expect(changes.count == 6)
    }

    @Test("Empty input returns empty array")
    func emptyInput() {
        let changes = FileChange.parseGitStatus("", repoRoot: repoRoot)
        #expect(changes.isEmpty)
    }

    @Test("Transcript entries have .transcript source")
    func transcriptSource() {
        let changes = FileChange.parseTranscript(Fixtures.transcriptJSONL)
        #expect(changes.allSatisfy { $0.source == .transcript })
    }

}
