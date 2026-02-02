// ABOUTME: Owns N terminal tabs, each with its own shell process and NSView.
// ABOUTME: Provides add/close/switch operations and exposes the active tab's state.

import SwiftUI
import SwiftTerm

@MainActor @Observable
final class TerminalTabManager {

    struct Tab: Identifiable {
        let id: UUID
        let viewModel: TerminalViewModel
        let terminalView: ResizableTerminalView
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

    func addTab(initialDirectory: String?, fontFamily: String, env: [String]? = nil) {
        lastDirectory = initialDirectory
        lastFontFamily = fontFamily
        let vm = TerminalViewModel()
        let view = ResizableTerminalView(frame: .zero)
        let coordinator = Coordinator(viewModel: vm)

        view.processDelegate = coordinator
        view.optionAsMetaKey = true
        view.caretViewTracksFocus = false
        view.font = FontSelection.terminalFont(family: fontFamily, size: 14)
        TerminalTheme.apply(to: view)

        let environment = env ?? Self.buildEnvironment()

        let executable = "/bin/zsh"
        let args = ["-l"]
        view.startProcess(
            executable: executable,
            args: args,
            environment: environment,
            execName: "zsh",
            currentDirectory: initialDirectory
        )
        vm.processStarted(executable: executable, args: args)

        // Hold a strong reference to the coordinator so it outlives the view
        objc_setAssociatedObject(view, &coordinatorKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let tab = Tab(id: UUID(), viewModel: vm, terminalView: view)
        tabs.append(tab)
        activeTabID = tab.id

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak view] in
            guard let view else { return }
            view.window?.makeFirstResponder(view)
            self?.applyCursorStyle(to: view)
        }
    }

    func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        let tab = tabs[index]
        // Terminate the shell process
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

    /// DECSCUSR base codes (blinking). Add 1 for steady variant.
    static let cursorStyleCodes: [String: Int] = [
        "block": 1,
        "underline": 3,
        "bar": 5,
    ]

    func applyCursorStyle(to view: ResizableTerminalView) {
        let pref = UserDefaults.standard.string(forKey: "cursorStyle") ?? "bar"
        let blink = UserDefaults.standard.object(forKey: "cursorBlink") as? Bool ?? true
        var code = Self.cursorStyleCodes[pref] ?? 5
        if !blink { code += 1 }
        view.feed(text: "\u{1b}[\(code) q")
    }

    func applyCursorStyleToAll() {
        for tab in tabs {
            applyCursorStyle(to: tab.terminalView)
        }
    }

    // MARK: - Focus

    private func focusActiveTab() {
        guard let view = activeTab?.terminalView else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak view] in
            view?.window?.makeFirstResponder(view)
        }
    }

    // MARK: - Environment

    static func buildEnvironment() -> [String] {
        var env: [String] = []
        let currentEnv = ProcessInfo.processInfo.environment
        for (key, value) in currentEnv {
            if key == "PATH" {
                let paths = ["/opt/homebrew/bin", "/usr/local/bin"]
                let existing = value.components(separatedBy: ":")
                let combined = (paths + existing).uniqued()
                env.append("PATH=\(combined.joined(separator: ":"))")
            } else {
                env.append("\(key)=\(value)")
            }
        }

        if !env.contains(where: { $0.hasPrefix("PATH=") }) {
            env.append("PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        }

        if !env.contains(where: { $0.hasPrefix("TERM=") }) {
            env.append("TERM=xterm-256color")
        }

        // Emit OSC 7 (current directory) on every prompt
        env.removeAll { $0.hasPrefix("TERM_PROGRAM=") }
        env.append("TERM_PROGRAM=Apple_Terminal")

        // Disable zsh session save/restore
        env.removeAll { $0.hasPrefix("SHELL_SESSIONS_DISABLE=") }
        env.append("SHELL_SESSIONS_DISABLE=1")

        return env
    }
}

// MARK: - Delegate Bridge

private nonisolated(unsafe) var coordinatorKey: UInt8 = 0

extension TerminalTabManager {
    @MainActor
    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let viewModel: TerminalViewModel

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }

        nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        }

        nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            DispatchQueue.main.async { [viewModel] in
                viewModel.titleChanged(title)
            }
        }

        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            DispatchQueue.main.async { [viewModel] in
                viewModel.directoryChanged(directory)
            }
        }

        nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
            DispatchQueue.main.async { [viewModel] in
                viewModel.processTerminated(exitCode: exitCode)
            }
        }
    }
}

// Utility to deduplicate arrays while preserving order
private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
