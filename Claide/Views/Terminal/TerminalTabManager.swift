// ABOUTME: Owns N terminal tabs, each with its own shell process and NSView.
// ABOUTME: Provides add/close/switch operations and exposes the active tab's state.

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
        let viewModel: TerminalViewModel
        let terminalView: MetalTerminalView
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
        let vm = TerminalViewModel()
        let view = MetalTerminalView(frame: .zero)

        let termSize = UserDefaults.standard.double(forKey: "terminalFontSize")
        view.terminalFont = FontSelection.terminalFont(family: fontFamily, size: termSize > 0 ? termSize : 14)

        let environment = env ?? Self.buildEnvironment()
        let directory = initialDirectory ?? NSHomeDirectory()

        view.startShell(
            executable: loginShell,
            args: ["-l"],
            environment: environment,
            directory: directory
        )
        vm.processStarted(executable: loginShell, args: ["-l"])

        // Wire up bridge events to view model
        view.bridge?.onTitle = { [weak vm] title in
            vm?.titleChanged(title)
        }
        view.bridge?.onDirectoryChange = { [weak vm] dir in
            vm?.directoryChanged(dir)
        }
        view.bridge?.onChildExit = { [weak vm] code in
            vm?.processTerminated(exitCode: code)
        }

        if let shellPid = view.bridge.map({ pid_t($0.shellPid) }), shellPid > 0 {
            vm.startTrackingForeground(shellPid: shellPid)
        }

        applyCursorStyle(to: view)

        let tab = Tab(id: UUID(), viewModel: vm, terminalView: view)
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

    func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let tab = tabs[index]
        tab.terminalView.terminate()
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
            applyCursorStyle(to: tab.terminalView)
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
