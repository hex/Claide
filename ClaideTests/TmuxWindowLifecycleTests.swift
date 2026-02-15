// ABOUTME: Tests for tmux window lifecycle: list-panes parsing and command queue.
// ABOUTME: Covers initial window enumeration, add/close/rename, and disconnect cleanup.

import Testing
@testable import Claide

@Suite("TmuxSessionManager — window list parsing")
struct TmuxWindowListParsingTests {

    @Test("single window with one pane")
    func singleWindow() {
        let response = "@0\t%0\tbash"
        let windows = TmuxSessionManager.parseWindowList(response)
        #expect(windows.count == 1)
        #expect(windows[0].windowID == 0)
        #expect(windows[0].paneID == 0)
        #expect(windows[0].name == "bash")
    }

    @Test("multiple windows")
    func multipleWindows() {
        let response = """
        @0\t%0\tbash
        @1\t%3\tvim
        @2\t%5\thtop
        """
        let windows = TmuxSessionManager.parseWindowList(response)
        #expect(windows.count == 3)
        #expect(windows[0].windowID == 0)
        #expect(windows[0].paneID == 0)
        #expect(windows[1].windowID == 1)
        #expect(windows[1].paneID == 3)
        #expect(windows[2].windowID == 2)
        #expect(windows[2].paneID == 5)
    }

    @Test("window name with spaces")
    func windowNameWithSpaces() {
        let response = "@3\t%7\tmy cool window"
        let windows = TmuxSessionManager.parseWindowList(response)
        #expect(windows.count == 1)
        #expect(windows[0].name == "my cool window")
    }

    @Test("window name with tabs")
    func windowNameWithTabs() {
        let response = "@0\t%0\tname\twith\ttabs"
        let windows = TmuxSessionManager.parseWindowList(response)
        #expect(windows.count == 1)
        #expect(windows[0].name == "name\twith\ttabs")
    }

    @Test("empty response returns empty array")
    func emptyResponse() {
        #expect(TmuxSessionManager.parseWindowList("").isEmpty)
    }

    @Test("malformed lines are skipped")
    func malformedLines() {
        let response = """
        @0\t%0\tbash
        garbage line
        @1\t%1\tzsh
        """
        let windows = TmuxSessionManager.parseWindowList(response)
        #expect(windows.count == 2)
    }

    @Test("missing window name uses empty string")
    func missingName() {
        let response = "@0\t%0"
        let windows = TmuxSessionManager.parseWindowList(response)
        #expect(windows.count == 1)
        #expect(windows[0].name == "")
    }

    @Test("pane ID parsing from single-pane response")
    func parsePaneID() {
        #expect(TmuxSessionManager.parsePaneID("%5") == 5)
        #expect(TmuxSessionManager.parsePaneID("%0") == 0)
        #expect(TmuxSessionManager.parsePaneID("%123\n") == 123)
    }

    @Test("pane ID parsing rejects invalid input")
    func parsePaneIDInvalid() {
        #expect(TmuxSessionManager.parsePaneID("") == nil)
        #expect(TmuxSessionManager.parsePaneID("@0") == nil)
        #expect(TmuxSessionManager.parsePaneID("garbage") == nil)
    }
}

@Suite("TmuxSessionManager — session list parsing")
struct TmuxSessionListParsingTests {

    @Test("single session")
    func singleSession() {
        let response = "main: 3 windows (created Sat Feb 15 10:00:00 2026)"
        let sessions = TmuxSessionManager.parseSessionList(response)
        #expect(sessions.count == 1)
        #expect(sessions[0].name == "main")
        #expect(sessions[0].windowCount == 3)
        #expect(sessions[0].isAttached == false)
    }

    @Test("attached session")
    func attachedSession() {
        let response = "dev: 2 windows (created Sat Feb 15 10:00:00 2026) (attached)"
        let sessions = TmuxSessionManager.parseSessionList(response)
        #expect(sessions.count == 1)
        #expect(sessions[0].name == "dev")
        #expect(sessions[0].isAttached == true)
    }

    @Test("multiple sessions")
    func multipleSessions() {
        let response = """
        main: 3 windows (created Sat Feb 15 10:00:00 2026) (attached)
        work: 1 windows (created Sat Feb 15 09:00:00 2026)
        test: 5 windows (created Fri Feb 14 20:00:00 2026)
        """
        let sessions = TmuxSessionManager.parseSessionList(response)
        #expect(sessions.count == 3)
        #expect(sessions[0].name == "main")
        #expect(sessions[0].isAttached == true)
        #expect(sessions[1].name == "work")
        #expect(sessions[1].windowCount == 1)
        #expect(sessions[2].name == "test")
    }

    @Test("empty response")
    func emptyResponse() {
        #expect(TmuxSessionManager.parseSessionList("").isEmpty)
    }

    @Test("session name with colon")
    func sessionNameWithColon() {
        let response = "my:session: 1 windows (created Sat Feb 15 10:00:00 2026)"
        let sessions = TmuxSessionManager.parseSessionList(response)
        #expect(sessions.count == 1)
        #expect(sessions[0].name == "my:session")
    }
}
