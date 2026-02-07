// ABOUTME: Owns N terminal tabs, each with a split-pane tree of shell processes.
// ABOUTME: Provides tab/pane add/close/split operations and exposes the active pane's state.

import SwiftUI

private let loginShell: String = {
    if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
        return shell
    }
    return "/bin/zsh"
}()

@MainActor @Observable
final class TerminalTabManager {

    struct Tab: Identifiable {
        let id: UUID
        let paneController: PaneTreeController
        var paneViewModels: [PaneID: TerminalViewModel]

        /// The active pane's view model (used for tab bar title, status, etc.)
        var viewModel: TerminalViewModel {
            paneViewModels[paneController.activePaneID]!
        }

        /// The active pane's terminal view.
        var terminalView: MetalTerminalView {
            (paneController.paneView(for: paneController.activePaneID) as? MetalTerminalView)!
        }

        /// All terminal views across all panes in this tab.
        var allTerminalViews: [MetalTerminalView] {
            paneController.paneTree.allPaneIDs.compactMap {
                paneController.paneView(for: $0) as? MetalTerminalView
            }
        }
    }

    private(set) var tabs: [Tab] = []
    var activeTabID: UUID?

    // Remembered from the most recent addTab call, used as defaults for menu-bar Cmd+T
    private var lastDirectory: String?
    private var lastFontFamily: String = ""

    var activeTab: Tab? {
        guard let id = activeTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    var activeViewModel: TerminalViewModel? {
        activeTab?.viewModel
    }

    // MARK: - Tab Lifecycle

    /// Add a tab reusing the active tab's directory and the last-used font.
    func addTab() {
        let dir = activeViewModel?.currentDirectory ?? lastDirectory
        addTab(initialDirectory: dir, fontFamily: lastFontFamily)
    }

    func addTab(initialDirectory: String?, fontFamily: String, env: [(String, String)]? = nil) {
        lastDirectory = initialDirectory
        lastFontFamily = fontFamily

        let environment = env ?? Self.buildEnvironment()
        let directory = initialDirectory ?? NSHomeDirectory()

        let controller = PaneTreeController { _ in
            MetalTerminalView(frame: .zero)
        }
        controller.onPaneCloseRequested = { [weak self] paneID in
            self?.closePane(paneID)
        }

        let initialID = controller.activePaneID
        guard let view = controller.paneView(for: initialID) as? MetalTerminalView else { return }

        let vm = TerminalViewModel()
        setupPane(paneID: initialID, controller: controller, view: view, viewModel: vm, directory: directory, environment: environment)

        let tab = Tab(id: UUID(), paneController: controller, paneViewModels: [initialID: vm])
        tabs.append(tab)
        activeTabID = tab.id

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak view] in
            guard let view else { return }
            view.window?.makeFirstResponder(view)
        }

        // Re-trigger resize after shell init completes.
        // The shell starts at 80x24 (default when frame is zero), autolayout resizes
        // almost immediately, but zsh ignores SIGWINCH during initialization
        // (before TRAPWINCH is installed). This nudge ensures final dimensions are applied.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak view] in
            guard let view, view.frame.width > 0 else { return }
            view.setFrameSize(view.frame.size)
        }
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              tabs.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex < tabs.count else { return }
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)
    }

    func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        for view in tabs[index].allTerminalViews {
            view.terminate()
        }
        tabs.remove(at: index)

        if activeTabID == id {
            // Select adjacent: prefer next, fall back to previous
            let newIndex = min(index, tabs.count - 1)
            activeTabID = tabs[newIndex].id
            focusActiveTab()
        }
    }

    func switchTo(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        focusActiveTab()
    }

    func switchToTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        switchTo(id: tabs[index].id)
    }

    func closeActiveTab() {
        guard let id = activeTabID else { return }
        closeTab(id: id)
    }

    // MARK: - Pane Operations

    /// Split the active pane along the given axis, spawning a new shell.
    func splitActivePane(axis: SplitAxis) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        // Read current directory before the split changes the active pane
        let dir = tabs[index].viewModel.currentDirectory ?? lastDirectory ?? NSHomeDirectory()
        let environment = Self.buildEnvironment()

        guard let newID = tabs[index].paneController.splitActivePane(axis: axis) else { return }
        guard let newView = tabs[index].paneController.paneView(for: newID) as? MetalTerminalView else { return }

        let vm = TerminalViewModel()
        tabs[index].paneViewModels[newID] = vm
        setupPane(paneID: newID, controller: tabs[index].paneController, view: newView, viewModel: vm, directory: dir, environment: environment)

        focusActiveTab()
    }

    /// Close a specific pane by ID. If it's the last pane in the tab, close the tab instead.
    func closePane(_ paneID: PaneID) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        if tabs[index].paneController.paneTree.paneCount > 1 {
            let closingView = tabs[index].paneController.paneView(for: paneID) as? MetalTerminalView

            if tabs[index].paneController.closePane(paneID) {
                closingView?.terminate()
                tabs[index].paneViewModels.removeValue(forKey: paneID)
                focusActiveTab()
            }
        } else {
            closeTab(id: tabs[index].id)
        }
    }

    /// Move focus to the adjacent pane in the given direction.
    func focusAdjacentPane(direction: PaneDirection) {
        guard let tab = activeTab else { return }
        if tab.paneController.focusAdjacentPane(direction: direction) {
            focusActiveTab()
        }
    }

    /// Close the active pane. If it's the last pane in the tab, close the tab instead.
    func closeActivePane() {
        guard let tab = activeTab else { return }
        closePane(tab.paneController.activePaneID)
    }

    // MARK: - Pane Setup

    private func setupPane(
        paneID: PaneID,
        controller: PaneTreeController,
        view: MetalTerminalView,
        viewModel: TerminalViewModel,
        directory: String,
        environment: [(String, String)]
    ) {
        let termSize = UserDefaults.standard.double(forKey: "terminalFontSize")
        view.terminalFont = FontSelection.terminalFont(
            family: lastFontFamily,
            size: termSize > 0 ? termSize : 14
        )

        view.startShell(
            executable: loginShell,
            args: ["-l"],
            environment: environment,
            directory: directory
        )
        viewModel.processStarted(executable: loginShell, args: ["-l"])

        view.bridge?.onTitle = { [weak viewModel, weak controller] title in
            viewModel?.titleChanged(title)
            controller?.setPaneTitle(title, for: paneID)
        }
        view.bridge?.onDirectoryChange = { [weak viewModel] dir in
            viewModel?.directoryChanged(dir)
        }
        view.bridge?.onChildExit = { [weak viewModel] code in
            viewModel?.processTerminated(exitCode: code)
        }

        if let shellPid = view.bridge.map({ pid_t($0.shellPid) }), shellPid > 0 {
            viewModel.startTrackingForeground(shellPid: shellPid)
        }

        applyCursorStyle(to: view)
        applyColorScheme(to: view)
    }

    // MARK: - Cursor Style

    func applyCursorStyle(to view: MetalTerminalView) {
        let pref = UserDefaults.standard.string(forKey: "cursorStyle") ?? "bar"
        let blink = UserDefaults.standard.object(forKey: "cursorBlink") as? Bool ?? true

        let shape: MetalTerminalView.CursorShape = switch pref {
        case "block": .block
        case "underline": .underline
        default: .beam
        }

        view.applyCursorPreferences(shape: shape, blinking: blink)
    }

    func applyCursorStyleToAll() {
        for tab in tabs {
            for view in tab.allTerminalViews {
                applyCursorStyle(to: view)
            }
        }
    }

    // MARK: - Color Scheme

    func applyColorScheme(to view: MetalTerminalView) {
        let schemeName = UserDefaults.standard.string(forKey: "terminalColorScheme") ?? "snazzy"
        let scheme = TerminalColorScheme.named(schemeName)
        view.applyColorScheme(scheme)
    }

    func applyColorSchemeToAll() {
        for tab in tabs {
            for view in tab.allTerminalViews {
                applyColorScheme(to: view)
            }
        }
    }

    // MARK: - Focus

    private func focusActiveTab() {
        guard let view = activeTab?.terminalView else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak view] in
            view?.window?.makeFirstResponder(view)
        }
    }

    // MARK: - Environment

    static func buildEnvironment() -> [(String, String)] {
        var env: [(String, String)] = []
        let currentEnv = ProcessInfo.processInfo.environment
        for (key, value) in currentEnv {
            if key == "PATH" {
                let paths = ["/opt/homebrew/bin", "/usr/local/bin"]
                let existing = value.components(separatedBy: ":")
                let combined = (paths + existing).uniqued()
                env.append((key, combined.joined(separator: ":")))
            } else {
                env.append((key, value))
            }
        }

        if !env.contains(where: { $0.0 == "PATH" }) {
            env.append(("PATH", "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"))
        }

        if !env.contains(where: { $0.0 == "TERM" }) {
            env.append(("TERM", "xterm-256color"))
        }

        // Emit OSC 7 (current directory) on every prompt
        env.removeAll { $0.0 == "TERM_PROGRAM" }
        env.append(("TERM_PROGRAM", "Apple_Terminal"))

        // Disable zsh session save/restore
        env.removeAll { $0.0 == "SHELL_SESSIONS_DISABLE" }
        env.append(("SHELL_SESSIONS_DISABLE", "1"))

        return env
    }
}

// Utility to deduplicate arrays while preserving order
private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
