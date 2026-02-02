// ABOUTME: Tests for parsing changes.md file format into FileChange models.
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
