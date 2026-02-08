// ABOUTME: Tests for TerminalTabManager tab lifecycle operations.
// ABOUTME: Verifies add, close, switch, and last-tab-protection behavior.

import Testing
import AppKit
@testable import Claide

@Suite("Terminal Tab Manager")
@MainActor
struct TerminalTabManagerTests {

    private func makeManager(tabCount: Int = 1) -> TerminalTabManager {
        let manager = TerminalTabManager()
        for _ in 0..<tabCount {
            manager.addTab(initialDirectory: nil, fontFamily: "", env: [
                ("PATH", "/usr/bin:/bin"),
                ("TERM", "xterm-256color"),
            ])
        }
        return manager
    }

    // MARK: - Add

    @Test("addTab creates a tab and makes it active")
    func addTabCreatesAndActivates() {
        let manager = makeManager(tabCount: 1)

        #expect(manager.tabs.count == 1)
        #expect(manager.activeTabID == manager.tabs[0].id)
        #expect(manager.activeTab != nil)
        #expect(manager.activeViewModel != nil)
        #expect(manager.activeViewModel?.isRunning == true)
    }

    @Test("addTab appends new tab and switches to it")
    func addTabAppendsAndSwitches() {
        let manager = makeManager(tabCount: 1)
        let firstID = manager.tabs[0].id

        manager.addTab(initialDirectory: nil, fontFamily: "", env: [
            ("PATH", "/usr/bin:/bin"),
            ("TERM", "xterm-256color"),
        ])

        #expect(manager.tabs.count == 2)
        #expect(manager.activeTabID == manager.tabs[1].id)
        #expect(manager.activeTabID != firstID)
    }

    // MARK: - Switch

    @Test("switchTo changes active tab")
    func switchToChangesActive() {
        let manager = makeManager(tabCount: 2)
        let firstID = manager.tabs[0].id

        // After adding 2 tabs, the second is active
        #expect(manager.activeTabID == manager.tabs[1].id)

        manager.switchTo(id: firstID)
        #expect(manager.activeTabID == firstID)
    }

    @Test("switchTo with invalid ID does nothing")
    func switchToInvalidID() {
        let manager = makeManager(tabCount: 1)
        let originalID = manager.activeTabID

        manager.switchTo(id: UUID())
        #expect(manager.activeTabID == originalID)
    }

    // MARK: - Close

    @Test("closeTab removes tab and selects adjacent")
    func closeTabRemovesAndSelectsAdjacent() {
        let manager = makeManager(tabCount: 3)
        let ids = manager.tabs.map(\.id)

        // Close the middle tab (index 1)
        // First switch to it so it's active
        manager.switchTo(id: ids[1])
        manager.closeTab(id: ids[1])

        #expect(manager.tabs.count == 2)
        #expect(!manager.tabs.contains(where: { $0.id == ids[1] }))
        // Should select the next tab (which is now at index 1, was index 2)
        #expect(manager.activeTabID == ids[2])
    }

    @Test("closeTab on last position selects previous")
    func closeLastPositionSelectsPrevious() {
        let manager = makeManager(tabCount: 2)
        let ids = manager.tabs.map(\.id)

        // Active is already the last tab (ids[1])
        manager.closeTab(id: ids[1])

        #expect(manager.tabs.count == 1)
        #expect(manager.activeTabID == ids[0])
    }

    @Test("closeTab refuses to close last remaining tab")
    func closeLastTabRefused() {
        let manager = makeManager(tabCount: 1)
        let id = manager.tabs[0].id

        manager.closeTab(id: id)

        #expect(manager.tabs.count == 1)
        #expect(manager.activeTabID == id)
    }

    @Test("closeTab with non-active tab preserves active selection")
    func closeNonActivePreservesSelection() {
        let manager = makeManager(tabCount: 3)
        let ids = manager.tabs.map(\.id)

        // Switch to first tab
        manager.switchTo(id: ids[0])

        // Close the last tab (not active)
        manager.closeTab(id: ids[2])

        #expect(manager.tabs.count == 2)
        #expect(manager.activeTabID == ids[0])
    }

    // MARK: - Environment

    @Test("buildEnvironment includes homebrew paths")
    func buildEnvironmentIncludesHomebrew() {
        let env = TerminalTabManager.buildEnvironment()

        let pathValue = env.first(where: { $0.0 == "PATH" })?.1
        #expect(pathValue != nil)
        #expect(pathValue!.contains("/opt/homebrew/bin"))
    }

    @Test("buildEnvironment sets TERM_PROGRAM to Claide")
    func buildEnvironmentSetsTermProgram() {
        let env = TerminalTabManager.buildEnvironment()

        let value = env.first(where: { $0.0 == "TERM_PROGRAM" })?.1
        #expect(value == "Claide")
    }

    @Test("buildEnvironment disables shell sessions")
    func buildEnvironmentDisablesShellSessions() {
        let env = TerminalTabManager.buildEnvironment()

        let value = env.first(where: { $0.0 == "SHELL_SESSIONS_DISABLE" })?.1
        #expect(value == "1")
    }

    // MARK: - Tab Identity

    @Test("each tab has a unique view model")
    func tabsHaveUniqueViewModels() {
        let manager = makeManager(tabCount: 2)

        let vm0 = manager.tabs[0].viewModel
        let vm1 = manager.tabs[1].viewModel
        #expect(vm0 !== vm1)
    }

    @Test("each tab has a unique terminal view")
    func tabsHaveUniqueTerminalViews() {
        let manager = makeManager(tabCount: 2)

        let view0 = manager.tabs[0].terminalView
        let view1 = manager.tabs[1].terminalView
        #expect(view0 !== view1)
    }

    // MARK: - Index-Based Switching

    @Test("switchToTab at valid index activates that tab")
    func switchToTabAtIndex() {
        let manager = makeManager(tabCount: 3)
        let ids = manager.tabs.map(\.id)

        manager.switchToTab(at: 0)
        #expect(manager.activeTabID == ids[0])

        manager.switchToTab(at: 2)
        #expect(manager.activeTabID == ids[2])
    }

    @Test("switchToTab at out-of-bounds index does nothing")
    func switchToTabOutOfBounds() {
        let manager = makeManager(tabCount: 2)
        let activeID = manager.activeTabID

        manager.switchToTab(at: 5)
        #expect(manager.activeTabID == activeID)

        manager.switchToTab(at: -1)
        #expect(manager.activeTabID == activeID)
    }

    // MARK: - Close Active Tab

    @Test("closeActiveTab closes the currently active tab")
    func closeActiveTabWorks() {
        let manager = makeManager(tabCount: 2)
        let firstID = manager.tabs[0].id

        // Active is tab 1 (second)
        manager.closeActiveTab()

        #expect(manager.tabs.count == 1)
        #expect(manager.activeTabID == firstID)
    }

    @Test("closeActiveTab does nothing when only one tab remains")
    func closeActiveTabRefusedOnLastTab() {
        let manager = makeManager(tabCount: 1)
        let id = manager.tabs[0].id

        manager.closeActiveTab()

        #expect(manager.tabs.count == 1)
        #expect(manager.activeTabID == id)
    }

    // MARK: - Grid Dimensions at Startup

    @Test("terminal view uses standard 80x24 when frame is zero")
    func gridDimensionsDefaultsAtZeroFrame() {
        let manager = makeManager(tabCount: 1)
        let view = manager.tabs[0].terminalView

        // View was created with frame: .zero — should fall back to 80x24, not 2x1
        let (cols, rows) = view.gridDimensions
        #expect(cols == 80)
        #expect(rows == 24)
    }

    // MARK: - Move Tab

    @Test("moveTab forward shifts tab to later position")
    func moveTabForward() {
        let manager = makeManager(tabCount: 3)
        let ids = manager.tabs.map(\.id)

        manager.moveTab(from: 0, to: 2)

        #expect(manager.tabs.map(\.id) == [ids[1], ids[2], ids[0]])
    }

    @Test("moveTab backward shifts tab to earlier position")
    func moveTabBackward() {
        let manager = makeManager(tabCount: 3)
        let ids = manager.tabs.map(\.id)

        manager.moveTab(from: 2, to: 0)

        #expect(manager.tabs.map(\.id) == [ids[2], ids[0], ids[1]])
    }

    @Test("moveTab to same index is a no-op")
    func moveTabSameIndex() {
        let manager = makeManager(tabCount: 3)
        let ids = manager.tabs.map(\.id)

        manager.moveTab(from: 1, to: 1)

        #expect(manager.tabs.map(\.id) == ids)
    }

    @Test("moveTab with out-of-bounds indices is a no-op")
    func moveTabOutOfBounds() {
        let manager = makeManager(tabCount: 3)
        let ids = manager.tabs.map(\.id)

        manager.moveTab(from: -1, to: 0)
        #expect(manager.tabs.map(\.id) == ids)

        manager.moveTab(from: 0, to: 5)
        #expect(manager.tabs.map(\.id) == ids)

        manager.moveTab(from: 3, to: 0)
        #expect(manager.tabs.map(\.id) == ids)
    }

    @Test("moveTab preserves active tab selection")
    func moveTabPreservesActive() {
        let manager = makeManager(tabCount: 3)
        let ids = manager.tabs.map(\.id)
        manager.switchTo(id: ids[0])

        manager.moveTab(from: 0, to: 2)

        // Active tab moved but stays active
        #expect(manager.activeTabID == ids[0])
    }

    @Test("moveTab adjacent swap works correctly")
    func moveTabAdjacentSwap() {
        let manager = makeManager(tabCount: 3)
        let ids = manager.tabs.map(\.id)

        manager.moveTab(from: 0, to: 1)
        #expect(manager.tabs.map(\.id) == [ids[1], ids[0], ids[2]])
    }

    // MARK: - No-Args addTab

    @Test("addTab with no args reuses last directory and font")
    func addTabNoArgsReusesDefaults() {
        let manager = TerminalTabManager()
        manager.addTab(initialDirectory: "/tmp", fontFamily: "Menlo", env: [
            ("PATH", "/usr/bin:/bin"),
            ("TERM", "xterm-256color"),
        ])

        #expect(manager.tabs.count == 1)

        // Now add without explicit args — should reuse active tab's config
        manager.addTab()

        #expect(manager.tabs.count == 2)
    }
}
