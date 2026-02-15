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
        let sessionStatusVM: SessionStatusViewModel
        let graphVM: GraphViewModel
        let fileLogVM: FileLogViewModel

        /// The active pane's view model (used for tab bar title, status, etc.)
        var viewModel: TerminalViewModel {
            paneViewModels[paneController.activePaneID]!
        }

        /// The active pane's terminal view.
        var terminalView: GhosttyTerminalView {
            (paneController.paneView(for: paneController.activePaneID) as? GhosttyTerminalView)!
        }

        /// All terminal views across all panes in this tab.
        var allTerminalViews: [GhosttyTerminalView] {
            paneController.paneTree.allPaneIDs.compactMap {
                paneController.paneView(for: $0) as? GhosttyTerminalView
            }
        }
    }

    private(set) var tabs: [Tab] = []
    var activeTabID: UUID?

    /// Called after color scheme is applied to all panes, allowing the window
    /// controller to update window chrome (e.g. background color).
    var onColorSchemeApplied: (() -> Void)?

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
            GhosttyTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }
        controller.onPaneCloseRequested = { [weak self] paneID in
            self?.closePane(paneID)
        }

        let initialID = controller.activePaneID
        guard let view = controller.paneView(for: initialID) as? GhosttyTerminalView else { return }

        let sessionStatusVM = SessionStatusViewModel()
        let graphVM = GraphViewModel()
        let fileLogVM = FileLogViewModel()

        let vm = TerminalViewModel()
        setupPane(paneID: initialID, controller: controller, view: view, viewModel: vm, directory: directory, environment: environment, sessionStatusVM: sessionStatusVM, fileLogVM: fileLogVM)

        sessionStatusVM.startWatching(sessionDirectory: directory)
        fileLogVM.startWatching(sessionDirectory: directory)

        let tab = Tab(id: UUID(), paneController: controller, paneViewModels: [initialID: vm], sessionStatusVM: sessionStatusVM, graphVM: graphVM, fileLogVM: fileLogVM)
        let position = UserDefaults.standard.string(forKey: "newTabPosition") ?? "end"
        if position == "afterCurrent",
           let activeID = activeTabID,
           let activeIndex = tabs.firstIndex(where: { $0.id == activeID }) {
            tabs.insert(tab, at: activeIndex + 1)
        } else {
            tabs.append(tab)
        }
        activeTabID = tab.id
        updateOcclusion()

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

    /// Restore a tab from saved session state.
    ///
    /// Creates the full pane tree and starts a shell in each pane's saved directory and profile.
    func restoreTab(state: TabState) {
        let environment = Self.buildEnvironment()

        let controller = PaneTreeController(
            restoredTree: state.paneTree,
            activePaneID: state.activePaneID
        ) { _ in
            GhosttyTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }
        controller.onPaneCloseRequested = { [weak self] paneID in
            self?.closePane(paneID)
        }

        let sessionStatusVM = SessionStatusViewModel()
        let graphVM = GraphViewModel()
        let fileLogVM = FileLogViewModel()

        var viewModels: [PaneID: TerminalViewModel] = [:]
        for paneID in state.paneTree.allPaneIDs {
            guard let view = controller.paneView(for: paneID) as? GhosttyTerminalView else { continue }
            let vm = TerminalViewModel()
            viewModels[paneID] = vm

            let dir = state.paneDirectories[paneID.uuidString] ?? NSHomeDirectory()
            let profile = state.paneProfiles?[paneID.uuidString] ?? .default
            setupPane(paneID: paneID, controller: controller, view: view, viewModel: vm, directory: dir, environment: environment, profile: profile, sessionStatusVM: sessionStatusVM, fileLogVM: fileLogVM)
        }

        // Derive the directory for VM initialization from the active pane's saved directory.
        let activeDir = state.paneDirectories[state.activePaneID.uuidString] ?? NSHomeDirectory()

        sessionStatusVM.startWatching(sessionDirectory: activeDir)
        fileLogVM.startWatching(sessionDirectory: activeDir)

        let tab = Tab(id: UUID(), paneController: controller, paneViewModels: viewModels, sessionStatusVM: sessionStatusVM, graphVM: graphVM, fileLogVM: fileLogVM)
        tabs.append(tab)
        activeTabID = tab.id
        updateOcclusion()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak controller] in
            guard let controller else { return }
            guard let view = controller.paneView(for: controller.activePaneID) as? GhosttyTerminalView else { return }
            view.window?.makeFirstResponder(view)
        }
    }

    // MARK: - Tmux Tab Lifecycle

    /// Create a tab backed by a tmux control mode pane.
    ///
    /// The shell runs a dummy command (`true`) — Ghostty keeps the surface alive
    /// while TmuxSessionManager feeds decoded output and intercepts input.
    func addTmuxTab(sessionManager: TmuxSessionManager, paneID: Int, title: String?) {
        let environment = Self.buildEnvironment()

        let controller = PaneTreeController { _ in
            GhosttyTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }
        controller.onPaneCloseRequested = { [weak self] claidePaneID in
            self?.closePane(claidePaneID)
        }

        let initialID = controller.activePaneID
        guard let view = controller.paneView(for: initialID) as? GhosttyTerminalView else { return }

        let sessionStatusVM = SessionStatusViewModel()
        let graphVM = GraphViewModel()
        let fileLogVM = FileLogViewModel()

        let vm = TerminalViewModel()
        vm.isTmuxPane = true
        vm.title = title ?? "tmux"

        setupTmuxPane(view: view, sessionManager: sessionManager, tmuxPaneID: paneID, environment: environment)

        let tab = Tab(id: UUID(), paneController: controller, paneViewModels: [initialID: vm], sessionStatusVM: sessionStatusVM, graphVM: graphVM, fileLogVM: fileLogVM)
        tabs.append(tab)
        activeTabID = tab.id
        updateOcclusion()

        sessionManager.register(view: view, forPane: paneID)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak view] in
            guard let view else { return }
            view.window?.makeFirstResponder(view)
        }
    }

    /// Configure a terminal view as a tmux display pane.
    private func setupTmuxPane(
        view: GhosttyTerminalView,
        sessionManager: TmuxSessionManager,
        tmuxPaneID: Int,
        environment: [(String, String)]
    ) {
        // Start a shell that exits immediately. Ghostty's wait_after_command
        // keeps the surface alive so we can feed output into it.
        view.startShell(environment: environment, directory: NSHomeDirectory())

        // Install input interceptor: keystrokes go to tmux, not the local shell.
        view.inputInterceptor = sessionManager.inputInterceptor(forPane: tmuxPaneID)
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

        tabs[index].sessionStatusVM.stopWatching()
        tabs[index].fileLogVM.stopWatching()
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
        updateOcclusion()
    }

    func closeOthersKeeping(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        for tab in tabs where tab.id != id {
            tab.sessionStatusVM.stopWatching()
            tab.fileLogVM.stopWatching()
            for view in tab.allTerminalViews {
                view.terminate()
            }
        }
        tabs.removeAll { $0.id != id }
        activeTabID = id
        updateOcclusion()
        focusActiveTab()
    }

    func closeToRight(afterId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == afterId }) else { return }
        let toRemove = tabs.suffix(from: index + 1)
        for tab in toRemove {
            tab.sessionStatusVM.stopWatching()
            tab.fileLogVM.stopWatching()
            for view in tab.allTerminalViews {
                view.terminate()
            }
        }
        let removedIDs = Set(toRemove.map(\.id))
        tabs.removeAll { removedIDs.contains($0.id) }
        if let activeTabID, removedIDs.contains(activeTabID) {
            self.activeTabID = afterId
            focusActiveTab()
        }
        updateOcclusion()
    }

    func closeAll() {
        for tab in tabs {
            tab.sessionStatusVM.stopWatching()
            tab.fileLogVM.stopWatching()
            for view in tab.allTerminalViews {
                view.terminate()
            }
        }
        tabs.removeAll()
        activeTabID = nil
    }

    func switchTo(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        updateOcclusion()
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
        guard let newView = tabs[index].paneController.paneView(for: newID) as? GhosttyTerminalView else { return }

        let vm = TerminalViewModel()
        tabs[index].paneViewModels[newID] = vm
        setupPane(paneID: newID, controller: tabs[index].paneController, view: newView, viewModel: vm, directory: dir, environment: environment, sessionStatusVM: tabs[index].sessionStatusVM, fileLogVM: tabs[index].fileLogVM)

        focusActiveTab()
    }

    /// Close a specific pane by ID. If it's the last pane in the tab, close the tab instead.
    func closePane(_ paneID: PaneID) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }

        if tabs[index].paneController.paneTree.paneCount > 1 {
            let closingView = tabs[index].paneController.paneView(for: paneID) as? GhosttyTerminalView

            if tabs[index].paneController.closePane(paneID) {
                closingView?.terminate()
                tabs[index].paneViewModels.removeValue(forKey: paneID)
                focusActiveTab()
            }
        } else {
            closeTab(id: tabs[index].id)
        }
    }

    /// Toggle zoom on the active pane (maximize / restore).
    func toggleZoom() {
        guard let tab = activeTab else { return }
        tab.paneController.toggleZoom()
        focusActiveTab()
    }

    /// Whether the active tab's pane layout is zoomed.
    var isZoomed: Bool {
        activeTab?.paneController.isZoomed ?? false
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
        view: GhosttyTerminalView,
        viewModel: TerminalViewModel,
        directory: String,
        environment: [(String, String)],
        profile: TerminalProfile = .default,
        sessionStatusVM: SessionStatusViewModel? = nil,
        fileLogVM: FileLogViewModel? = nil
    ) {
        viewModel.profile = profile
        let shell = profile.resolvedShell

        // Override SHELL if the profile specifies a custom shell.
        // Ghostty reads SHELL to determine which shell to launch via login(1).
        var env = environment
        if profile.shell != nil {
            env.append(("SHELL", shell))
        }

        let pidsBefore = Self.childPids()
        view.startShell(environment: env, directory: directory)
        viewModel.processStarted(executable: shell, args: [])

        // Detect the shell PID by diffing Claide's children before/after spawn.
        // The direct child may be login(1), which wraps the actual shell, so we
        // walk the child tree to find the process matching our target shell.
        // Once found, foreground tracking polls the shell's children to detect
        // when a command is actively running (shows spinner in the tab bar).
        Task { @MainActor [weak viewModel, weak sessionStatusVM, weak fileLogVM] in
            var directChild: pid_t?
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(100))
                let newPids = Self.childPids().subtracting(pidsBefore)
                if let pid = newPids.first {
                    directChild = pid
                    break
                }
            }
            guard let directChild else { return }

            // Wait for the login -> shell chain to establish
            try? await Task.sleep(for: .milliseconds(300))
            let shellPid = Self.resolveShellPid(from: directChild, shell: shell)
            viewModel?.startTrackingForeground(shellPid: shellPid)
            sessionStatusVM?.addShellPid(shellPid)
            fileLogVM?.addShellPid(shellPid)
        }

        view.onTitle = { [weak viewModel, weak controller] title in
            viewModel?.titleChanged(title)
            controller?.setPaneTitle(title, for: paneID)
        }
        view.onDirectoryChange = { [weak viewModel] dir in
            viewModel?.directoryChanged(dir)
        }
        view.onChildExit = { [weak viewModel] code in
            viewModel?.processTerminated(exitCode: code)
        }
        view.onBell = {
            let bellStyle = UserDefaults.standard.string(forKey: "bellStyle") ?? "visual"
            switch bellStyle {
            case "none":
                break
            case "audio":
                NSSound.beep()
                if !NSApp.isActive {
                    NSApp.requestUserAttention(.informationalRequest)
                }
            default: // "visual"
                if !NSApp.isActive {
                    NSApp.requestUserAttention(.informationalRequest)
                }
            }
        }
        view.onProgressReport = { [weak viewModel] state, progress in
            Task { @MainActor in
                viewModel?.progressReported(state: state, progress: progress)
            }
        }

        view.onFocused = { [weak controller] in
            controller?.focusPane(paneID)
        }

        // Color scheme for pane dividers
        let scheme = ChromeColorScheme.named(profile.resolvedColorScheme)
        controller.containerView.applyColorScheme(scheme, for: paneID)
    }

    // MARK: - Color Scheme

    func applyColorSchemeToAll() {
        for tab in tabs {
            for (paneID, vm) in tab.paneViewModels {
                let scheme = ChromeColorScheme.named(vm.profile.resolvedColorScheme)
                tab.paneController.containerView.applyColorScheme(scheme, for: paneID)
            }
        }
        onColorSchemeApplied?()
    }

    // MARK: - Pane Focus

    func applyPaneFocusSettingsToAll() {
        for tab in tabs {
            tab.paneController.containerView.setActivePaneID(tab.paneController.activePaneID)
            for (paneID, _) in tab.paneViewModels {
                guard let view = tab.paneController.paneView(for: paneID) as? GhosttyTerminalView else { continue }
                let isFocused = (view == view.window?.firstResponder as? GhosttyTerminalView)
                let dim = UserDefaults.standard.bool(forKey: "dimUnfocusedPanes")
                view.alphaValue = (isFocused || !dim) ? 1.0 : 0.6
            }
        }
    }

    // MARK: - Occlusion

    private func updateOcclusion() {
        for tab in tabs {
            let occluded = (tab.id != activeTabID)
            for view in tab.allTerminalViews {
                view.setOccluded(occluded)
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

    /// Snapshot of Claide's direct child PIDs (used to detect newly forked shells).
    private static func childPids() -> Set<pid_t> {
        var pids = [pid_t](repeating: 0, count: 256)
        let byteSize = Int32(pids.count * MemoryLayout<pid_t>.size)
        let count = Int(proc_listchildpids(getpid(), &pids, byteSize))
        guard count > 0 else { return [] }
        return Set(pids.prefix(count))
    }

    /// Walk from a direct child PID (often login(1)) to find the actual shell.
    /// Matches by executable name since login may wrap the shell as a child process.
    private static func resolveShellPid(from pid: pid_t, shell: String) -> pid_t {
        let shellName = (shell as NSString).lastPathComponent

        // Check if this process IS the shell
        if let path = TerminalViewModel.executablePath(for: pid),
           (path as NSString).lastPathComponent == shellName {
            return pid
        }

        // Check one level of children for the shell
        var children = [pid_t](repeating: 0, count: 16)
        let byteSize = Int32(children.count * MemoryLayout<pid_t>.size)
        let count = Int(proc_listchildpids(pid, &children, byteSize))
        for child in children.prefix(max(count, 0)) {
            if let path = TerminalViewModel.executablePath(for: child),
               (path as NSString).lastPathComponent == shellName {
                return child
            }
        }

        // Fallback: use the direct child (best effort)
        return pid
    }

    /// Claide-specific env vars to inject into child shells.
    /// Ghostty inherits the process environment automatically via getEnvMap();
    /// these are applied as overrides on top. The process environment is clean
    /// because Claide is launched via launchd (not `open`).
    static func buildEnvironment() -> [(String, String)] {
        [
            ("TERM_PROGRAM", "Claide"),
            ("SHELL_SESSIONS_DISABLE", "1"),
            ("CLAIDE_PID", "\(getpid())"),
        ]
    }
}
