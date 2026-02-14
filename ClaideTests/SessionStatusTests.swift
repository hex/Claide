// ABOUTME: Tests for SessionStatus JSONL parsing and formatted output.
// ABOUTME: Validates extraction of token usage from Claude Code transcript entries.

import Testing
import Foundation
@testable import Claide

@Suite("Session Status Parsing")
struct SessionStatusTests {

    // MARK: - JSONL Transcript Parsing

    static func assistantEntry(
        inputTokens: Int, outputTokens: Int,
        cacheCreation: Int, cacheRead: Int,
        model: String = "claude-opus-4-5-20251101"
    ) -> String {
        """
        {"type":"assistant","message":{"model":"\(model)","role":"assistant","content":[],"usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens),"cache_creation_input_tokens":\(cacheCreation),"cache_read_input_tokens":\(cacheRead)}}}
        """
    }

    static let userEntry = """
    {"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}
    """

    @Test("Parses last assistant entry from transcript tail")
    func parsesLastAssistant() throws {
        let lines = [
            Self.assistantEntry(inputTokens: 100, outputTokens: 50, cacheCreation: 1000, cacheRead: 80000),
            Self.userEntry,
            Self.assistantEntry(inputTokens: 200, outputTokens: 60, cacheCreation: 2000, cacheRead: 85000),
        ].joined(separator: "\n")
        let data = Data(lines.utf8)
        let status = try #require(SessionStatus.fromTranscriptTail(data))
        // Should pick the last assistant: 200 + 2000 + 85000 = 87200
        #expect(status.totalInputTokens == 87_200)
    }

    @Test("Skips user entries to find assistant")
    func skipsUserEntries() throws {
        let lines = [
            Self.assistantEntry(inputTokens: 1, outputTokens: 10, cacheCreation: 500, cacheRead: 140000),
            Self.userEntry,
            Self.userEntry,
        ].joined(separator: "\n")
        let data = Data(lines.utf8)
        let status = try #require(SessionStatus.fromTranscriptTail(data))
        #expect(status.totalInputTokens == 140_501)
    }

    @Test("Returns nil for empty data")
    func returnsNilForEmpty() {
        let status = SessionStatus.fromTranscriptTail(Data())
        #expect(status == nil)
    }

    @Test("Returns nil when no assistant entries exist")
    func returnsNilForNoAssistant() {
        let data = Data(Self.userEntry.utf8)
        let status = SessionStatus.fromTranscriptTail(data)
        #expect(status == nil)
    }

    // MARK: - Computed Properties

    @Test("Computes used percentage")
    func computesPercentage() {
        let status = SessionStatus(totalInputTokens: 140_000, outputTokens: 100, contextWindowSize: 200_000)
        #expect(status.usedPercentage == 70.0)
    }

    @Test("Percentage is zero when context window is zero")
    func percentageZeroDivision() {
        let status = SessionStatus(totalInputTokens: 100, outputTokens: 10, contextWindowSize: 0)
        #expect(status.usedPercentage == 0)
    }

    @Test("Formats usage string with grouping separators")
    func formatsUsage() {
        let status = SessionStatus(totalInputTokens: 146_645, outputTokens: 100, contextWindowSize: 200_000)
        #expect(status.formattedUsage == "146,645 / 200,000 (73%)")
    }

    @Test("Formats zero tokens")
    func formatsZeroTokens() {
        let status = SessionStatus(totalInputTokens: 0, outputTokens: 0, contextWindowSize: 200_000)
        #expect(status.formattedUsage == "0 / 200,000 (0%)")
    }

    @Test("Formats high usage near compaction")
    func formatsHighUsage() {
        let status = SessionStatus(totalInputTokens: 180_000, outputTokens: 500, contextWindowSize: 200_000)
        #expect(status.formattedUsage == "180,000 / 200,000 (90%)")
    }

    // MARK: - Transcript Path Discovery

    @Test("Encodes session directory to Claude project path")
    func encodesProjectPath() {
        let dir = SessionStatusViewModel.projectDirectory(for: "/Users/hex/.claude-sessions/claide")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expected = (home as NSString).appendingPathComponent(
            ".claude/projects/-Users-hex--claude-sessions-claide"
        )
        #expect(dir == expected)
    }

    @Test("Returns nil for nonexistent session directory")
    func returnsNilForNonexistent() {
        let path = SessionStatusViewModel.findTranscript(sessionDirectory: "/nonexistent/path")
        #expect(path == nil)
    }

    // MARK: - Process Environment Detection

    @Test("Finds HOME env var in own process")
    func findsHomeEnvVar() {
        let home = ProcessInfo.processInfo.environment["HOME"]!
        let found = SessionStatusViewModel.processHasEnvVar(
            pid: getpid(), key: "HOME", value: home
        )
        #expect(found == true)
    }

    @Test("Returns false for nonexistent env var")
    func returnsFalseForMissingVar() {
        let found = SessionStatusViewModel.processHasEnvVar(
            pid: getpid(), key: "CLAIDE_NONEXISTENT_VAR_12345", value: "x"
        )
        #expect(found == false)
    }

    @Test("Returns false for invalid PID")
    func returnsFalseForInvalidPid() {
        let found = SessionStatusViewModel.processHasEnvVar(
            pid: -1, key: "HOME", value: "/tmp"
        )
        #expect(found == false)
    }

    @Test("Returns false when value does not match")
    func returnsFalseWhenValueMismatches() {
        let found = SessionStatusViewModel.processHasEnvVar(
            pid: getpid(), key: "HOME", value: "/nonexistent/wrong/path"
        )
        #expect(found == false)
    }

    @Test("processArgv0Basename returns non-nil for own process")
    func argv0BasenameForOwnProcess() {
        let name = SessionStatusViewModel.processArgv0Basename(pid: getpid())
        #expect(name != nil)
        #expect(name?.isEmpty == false)
    }

    @Test("processArgv0Basename returns nil for invalid PID")
    func argv0BasenameForInvalidPid() {
        let name = SessionStatusViewModel.processArgv0Basename(pid: -1)
        #expect(name == nil)
    }

    @Test("processWorkingDirectory returns cwd for own process")
    func cwdForOwnProcess() {
        let cwd = SessionStatusViewModel.processWorkingDirectory(pid: getpid())
        #expect(cwd != nil)
        #expect(cwd?.isEmpty == false)
    }

    @Test("processWorkingDirectory returns nil for invalid PID")
    func cwdForInvalidPid() {
        let cwd = SessionStatusViewModel.processWorkingDirectory(pid: -1)
        #expect(cwd == nil)
    }

    @Test("findClaudeForClaide returns nil when no Claude is running")
    func findClaudeReturnsNilWhenNoneRunning() {
        // During tests, no Claude Code process with our CLAIDE_PID should exist
        let result = SessionStatusViewModel.findClaudeForClaide()
        #expect(result == nil)
    }

    @Test("buildEnvironment contains CLAIDE_PID with current PID")
    @MainActor func buildEnvironmentContainsClaidePid() {
        let env = TerminalTabManager.buildEnvironment()
        let entry = env.first { $0.0 == "CLAIDE_PID" }
        #expect(entry != nil)
        #expect(entry?.1 == "\(getpid())")
    }

    // MARK: - Partial tail handling

    @Test("Handles truncated first line in tail chunk")
    func handlesTruncatedFirstLine() throws {
        let full = Self.assistantEntry(inputTokens: 1, outputTokens: 5, cacheCreation: 100, cacheRead: 50000)
        // Simulate a tail read that chops the first line mid-JSON
        let truncated = "...broken json}\n" + full
        let data = Data(truncated.utf8)
        let status = try #require(SessionStatus.fromTranscriptTail(data))
        #expect(status.totalInputTokens == 50_101)
    }
}
