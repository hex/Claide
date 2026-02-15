// ABOUTME: TDD tests for TmuxProtocolParser — tmux control mode line protocol.
// ABOUTME: Covers %output octal escapes, %begin/%end blocks, window lifecycle, edge cases.

import Testing
import Foundation
@testable import Claide

// MARK: - Test Helpers

/// Collects notifications from a parser for assertion.
private func collectNotifications(from lines: [String]) -> [TmuxNotification] {
    let parser = TmuxProtocolParser()
    var results: [TmuxNotification] = []
    parser.onNotification = { results.append($0) }
    for line in lines {
        parser.feed(line: line)
    }
    return results
}

/// Shorthand: feed lines, expect exactly one notification.
private func parseSingle(_ line: String) -> TmuxNotification? {
    let results = collectNotifications(from: [line])
    return results.count == 1 ? results[0] : nil
}

// MARK: - %output

@Suite("TmuxProtocolParser — %output")
struct TmuxOutputTests {

    @Test("plain ASCII output")
    func plainAscii() {
        let notification = parseSingle("%output %0 hello world")
        #expect(notification == .output(paneID: 0, data: Data("hello world".utf8)))
    }

    @Test("output from higher pane ID")
    func higherPaneID() {
        let notification = parseSingle("%output %42 data")
        #expect(notification == .output(paneID: 42, data: Data("data".utf8)))
    }

    @Test("output with octal-escaped newline")
    func octalNewline() {
        // \012 is octal for 0x0A (newline)
        let notification = parseSingle("%output %0 line1\\012line2")
        let expected = Data([0x6C, 0x69, 0x6E, 0x65, 0x31, 0x0A, 0x6C, 0x69, 0x6E, 0x65, 0x32])
        #expect(notification == .output(paneID: 0, data: expected))
    }

    @Test("output with octal-escaped carriage return and newline")
    func octalCRLF() {
        // \015\012 = CR LF
        let notification = parseSingle("%output %0 hello\\015\\012")
        var expected = Data("hello".utf8)
        expected.append(contentsOf: [0x0D, 0x0A])
        #expect(notification == .output(paneID: 0, data: expected))
    }

    @Test("output with escaped backslash")
    func escapedBackslash() {
        // \134 is octal for backslash (0x5C)
        let notification = parseSingle("%output %0 path\\134file")
        let expected = Data("path\\file".utf8)
        #expect(notification == .output(paneID: 0, data: expected))
    }

    @Test("output with multiple octal escapes")
    func multipleOctalEscapes() {
        // ESC [ 3 1 m = \033[31m (red ANSI color)
        let notification = parseSingle("%output %0 \\033[31mred\\033[0m")
        var expected = Data()
        expected.append(0x1B) // ESC
        expected.append(contentsOf: "[31m".utf8)
        expected.append(contentsOf: "red".utf8)
        expected.append(0x1B) // ESC
        expected.append(contentsOf: "[0m".utf8)
        #expect(notification == .output(paneID: 0, data: expected))
    }

    @Test("output with empty data after pane ID")
    func emptyOutput() {
        let notification = parseSingle("%output %0 ")
        #expect(notification == .output(paneID: 0, data: Data()))
    }

    @Test("output with spaces in data")
    func spacesInData() {
        let notification = parseSingle("%output %1 hello  world  ")
        #expect(notification == .output(paneID: 1, data: Data("hello  world  ".utf8)))
    }

    @Test("output with high byte octal escape")
    func highByteOctal() {
        // \377 = 0xFF
        let notification = parseSingle("%output %0 \\377")
        #expect(notification == .output(paneID: 0, data: Data([0xFF])))
    }

    @Test("output with NUL byte octal escape")
    func nulByteOctal() {
        // \000 = 0x00
        let notification = parseSingle("%output %0 \\000")
        #expect(notification == .output(paneID: 0, data: Data([0x00])))
    }
}

// MARK: - %begin / %end / %error blocks

@Suite("TmuxProtocolParser — command response blocks")
struct TmuxBlockTests {

    @Test("simple begin/end block with single line response")
    func simpleBlock() {
        let lines = [
            "%begin 1234567890 1 0",
            "some response",
            "%end 1234567890 1 0",
        ]
        let results = collectNotifications(from: lines)
        #expect(results.count == 1)
        #expect(results[0] == .blockEnd(commandNumber: 1, data: "some response"))
    }

    @Test("begin/end block with multi-line response")
    func multiLineBlock() {
        let lines = [
            "%begin 1234567890 2 0",
            "line one",
            "line two",
            "line three",
            "%end 1234567890 2 0",
        ]
        let results = collectNotifications(from: lines)
        #expect(results.count == 1)
        #expect(results[0] == .blockEnd(commandNumber: 2, data: "line one\nline two\nline three"))
    }

    @Test("begin/error block emits blockError")
    func errorBlock() {
        let lines = [
            "%begin 1234567890 3 0",
            "no such session: foo",
            "%error 1234567890 3 0",
        ]
        let results = collectNotifications(from: lines)
        #expect(results.count == 1)
        #expect(results[0] == .blockError(commandNumber: 3, data: "no such session: foo"))
    }

    @Test("empty begin/end block")
    func emptyBlock() {
        let lines = [
            "%begin 1234567890 4 0",
            "%end 1234567890 4 0",
        ]
        let results = collectNotifications(from: lines)
        #expect(results.count == 1)
        #expect(results[0] == .blockEnd(commandNumber: 4, data: ""))
    }

    @Test("notifications interleaved with block lines")
    func interleavedNotifications() {
        // %output can arrive while a block is in progress
        let lines = [
            "%begin 1234567890 5 0",
            "%output %0 hello",
            "response data",
            "%end 1234567890 5 0",
        ]
        let results = collectNotifications(from: lines)
        // %output should be emitted immediately, block end comes after
        #expect(results.count == 2)
        #expect(results[0] == .output(paneID: 0, data: Data("hello".utf8)))
        #expect(results[1] == .blockEnd(commandNumber: 5, data: "response data"))
    }

    @Test("block with command number parsing")
    func commandNumberParsing() {
        let lines = [
            "%begin 9999 100 1",
            "data",
            "%end 9999 100 1",
        ]
        let results = collectNotifications(from: lines)
        #expect(results.count == 1)
        #expect(results[0] == .blockEnd(commandNumber: 100, data: "data"))
    }
}

// MARK: - Window lifecycle

@Suite("TmuxProtocolParser — window notifications")
struct TmuxWindowTests {

    @Test("window-add")
    func windowAdd() {
        let notification = parseSingle("%window-add @1")
        #expect(notification == .windowAdd(windowID: 1))
    }

    @Test("window-close")
    func windowClose() {
        let notification = parseSingle("%window-close @3")
        #expect(notification == .windowClose(windowID: 3))
    }

    @Test("window-renamed")
    func windowRenamed() {
        let notification = parseSingle("%window-renamed @2 my-server")
        #expect(notification == .windowRenamed(windowID: 2, name: "my-server"))
    }

    @Test("window-renamed with spaces in name")
    func windowRenamedWithSpaces() {
        let notification = parseSingle("%window-renamed @0 my long name")
        #expect(notification == .windowRenamed(windowID: 0, name: "my long name"))
    }

    @Test("layout-change")
    func layoutChange() {
        let notification = parseSingle("%layout-change @1 abcd,200x50,0,0,1")
        #expect(notification == .layoutChange(windowID: 1, layout: "abcd,200x50,0,0,1"))
    }

    @Test("window-pane-changed")
    func windowPaneChanged() {
        let notification = parseSingle("%window-pane-changed @0 %5")
        #expect(notification == .windowPaneChanged(windowID: 0, paneID: 5))
    }
}

// MARK: - Session and pane notifications

@Suite("TmuxProtocolParser — session and pane notifications")
struct TmuxSessionPaneTests {

    @Test("session-changed")
    func sessionChanged() {
        let notification = parseSingle("%session-changed $1 my-session")
        #expect(notification == .sessionChanged(sessionID: 1, name: "my-session"))
    }

    @Test("session-changed with spaces in name")
    func sessionChangedWithSpaces() {
        let notification = parseSingle("%session-changed $0 dev session alpha")
        #expect(notification == .sessionChanged(sessionID: 0, name: "dev session alpha"))
    }

    @Test("sessions-changed")
    func sessionsChanged() {
        let notification = parseSingle("%sessions-changed")
        #expect(notification == .sessionsChanged)
    }

    @Test("pane-mode-changed")
    func paneModeChanged() {
        let notification = parseSingle("%pane-mode-changed %3")
        #expect(notification == .paneModeChanged(paneID: 3))
    }
}

// MARK: - Exit

@Suite("TmuxProtocolParser — exit")
struct TmuxExitTests {

    @Test("exit without reason")
    func exitNoReason() {
        let notification = parseSingle("%exit")
        #expect(notification == .exit(reason: nil))
    }

    @Test("exit with reason")
    func exitWithReason() {
        let notification = parseSingle("%exit client detached")
        #expect(notification == .exit(reason: "client detached"))
    }
}

// MARK: - Edge cases

@Suite("TmuxProtocolParser — edge cases")
struct TmuxEdgeCaseTests {

    @Test("unrecognized notification stored for forward-compatibility")
    func unrecognizedNotification() {
        let notification = parseSingle("%future-notification some data")
        #expect(notification == .unrecognized(line: "%future-notification some data"))
    }

    @Test("non-notification line outside block is ignored")
    func nonNotificationLine() {
        let results = collectNotifications(from: ["just a plain line"])
        #expect(results.isEmpty)
    }

    @Test("empty line is ignored")
    func emptyLine() {
        let results = collectNotifications(from: [""])
        #expect(results.isEmpty)
    }

    @Test("multiple notifications in sequence")
    func multipleNotifications() {
        let lines = [
            "%window-add @0",
            "%output %0 hello",
            "%window-renamed @0 bash",
        ]
        let results = collectNotifications(from: lines)
        #expect(results.count == 3)
        #expect(results[0] == .windowAdd(windowID: 0))
        #expect(results[1] == .output(paneID: 0, data: Data("hello".utf8)))
        #expect(results[2] == .windowRenamed(windowID: 0, name: "bash"))
    }

    @Test("line with only % prefix but no valid type")
    func barePercentPrefix() {
        let notification = parseSingle("%")
        #expect(notification == .unrecognized(line: "%"))
    }

    @Test("output with trailing carriage return stripped")
    func trailingCR() {
        // tmux sometimes sends lines with \r at end
        let notification = parseSingle("%output %0 data\r")
        // The \r is part of the line content, not the data payload
        // Parser should handle this by stripping trailing \r from lines
        #expect(notification == .output(paneID: 0, data: Data("data".utf8)))
    }
}

// MARK: - Octal unescape utility

@Suite("TmuxProtocolParser — octal unescape")
struct TmuxOctalUnescapeTests {

    @Test("string with no escapes returns identical bytes")
    func noEscapes() {
        let result = TmuxProtocolParser.octalUnescape("hello")
        #expect(result == Data("hello".utf8))
    }

    @Test("all-escaped string")
    func allEscaped() {
        // \110\145\154\154\157 = "Hello"
        let result = TmuxProtocolParser.octalUnescape("\\110\\145\\154\\154\\157")
        #expect(result == Data("Hello".utf8))
    }

    @Test("mixed escaped and literal")
    func mixedContent() {
        let result = TmuxProtocolParser.octalUnescape("A\\012B")
        #expect(result == Data([0x41, 0x0A, 0x42]))
    }

    @Test("backslash not followed by three octal digits is literal")
    func incompleteEscape() {
        // \12 (only 2 digits) — treat as literal characters
        let result = TmuxProtocolParser.octalUnescape("\\12x")
        #expect(result == Data("\\12x".utf8))
    }

    @Test("backslash at end of string is literal")
    func trailingBackslash() {
        let result = TmuxProtocolParser.octalUnescape("end\\")
        #expect(result == Data("end\\".utf8))
    }

    @Test("empty string returns empty data")
    func emptyString() {
        let result = TmuxProtocolParser.octalUnescape("")
        #expect(result == Data())
    }
}
