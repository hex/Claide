// ABOUTME: Tests for tmux-native split and close routing in TerminalTabManager.
// ABOUTME: Verifies that splits/closes on tmux panes go through tmux commands, not local operations.

import Testing
@testable import Claide

@Suite("TerminalTabManager — tmux pane ID lookup")
@MainActor
struct TmuxPaneIDLookupTests {

    @Test("tmuxPaneID returns nil for non-tmux pane")
    func nonTmuxPaneReturnsNil() {
        let manager = TerminalTabManager()
        manager.addTab(initialDirectory: nil, fontFamily: "", env: [
            ("PATH", "/usr/bin:/bin"),
            ("TERM", "xterm-256color"),
        ])

        let paneID = manager.activeTab!.paneController.activePaneID
        #expect(manager.tmuxPaneID(for: paneID) == nil)
    }

    @Test("tmuxPaneID returns correct tmux ID for registered pane")
    func registeredPaneReturnsTmuxID() {
        let manager = TerminalTabManager()
        manager.addTab(initialDirectory: nil, fontFamily: "", env: [
            ("PATH", "/usr/bin:/bin"),
            ("TERM", "xterm-256color"),
        ])

        let claidePaneID = manager.activeTab!.paneController.activePaneID
        let tabID = manager.activeTabID!
        // Simulate tmux pane registration
        manager.registerTmuxPaneMapping(tmuxPaneID: 42, tabID: tabID, claidePaneID: claidePaneID)

        #expect(manager.tmuxPaneID(for: claidePaneID) == 42)
    }

    @Test("tmuxPaneID returns nil after pane mapping is removed")
    func removedMappingReturnsNil() {
        let manager = TerminalTabManager()
        manager.addTab(initialDirectory: nil, fontFamily: "", env: [
            ("PATH", "/usr/bin:/bin"),
            ("TERM", "xterm-256color"),
        ])

        let claidePaneID = manager.activeTab!.paneController.activePaneID
        let tabID = manager.activeTabID!
        manager.registerTmuxPaneMapping(tmuxPaneID: 7, tabID: tabID, claidePaneID: claidePaneID)
        manager.removeTmuxPaneMapping(tmuxPaneID: 7)

        #expect(manager.tmuxPaneID(for: claidePaneID) == nil)
    }
}

@Suite("TerminalTabManager — duplicate tmux tab prevention")
@MainActor
struct TmuxDuplicateTabTests {

    @Test("addTmuxTab ignores duplicate window IDs")
    func duplicateWindowIDIgnored() {
        let manager = TerminalTabManager()
        let channel = TmuxControlChannel()
        let session = TmuxSessionManager(channel: channel)

        // First call creates the tab.
        manager.addTmuxTab(sessionManager: session, windowID: 0, paneID: 0, title: "bash")
        #expect(manager.tabs.count == 1)

        // Second call with the same windowID should be ignored.
        manager.addTmuxTab(sessionManager: session, windowID: 0, paneID: 1, title: "bash")
        #expect(manager.tabs.count == 1)
    }
}

@Suite("TerminalTabManager — tmux split command")
struct TmuxSplitCommandTests {

    @Test("horizontal split produces -h flag")
    func horizontalSplit() {
        let cmd = TerminalTabManager.tmuxSplitCommand(axis: .horizontal, tmuxPaneID: 5)
        #expect(cmd == "split-window -h -t %5")
    }

    @Test("vertical split produces -v flag")
    func verticalSplit() {
        let cmd = TerminalTabManager.tmuxSplitCommand(axis: .vertical, tmuxPaneID: 12)
        #expect(cmd == "split-window -v -t %12")
    }
}

@Suite("TerminalTabManager — tmux close command")
struct TmuxCloseCommandTests {

    @Test("kill-pane command is correctly formed")
    func killPaneCommand() {
        let cmd = TerminalTabManager.tmuxKillPaneCommand(tmuxPaneID: 3)
        #expect(cmd == "kill-pane -t %3")
    }
}
