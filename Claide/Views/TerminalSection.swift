// ABOUTME: Left pane of the main split: tab bar, terminal panel, and status bar.
// ABOUTME: Owns session-scoped view models and wires terminal lifecycle events.

import SwiftUI

struct TerminalSection: View {
    let tabManager: TerminalTabManager
    @State private var sessionStatusVM = SessionStatusViewModel()
    @AppStorage("fontFamily") private var fontFamily: String = ""
    @AppStorage("cursorStyle") private var cursorStyle: String = "bar"
    @AppStorage("cursorBlink") private var cursorBlink: Bool = true
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"
    @AppStorage("paneFocusIndicator") private var paneFocusIndicator = true
    @AppStorage("dimUnfocusedPanes") private var dimUnfocusedPanes = true

    private static let initialDirectory: String = {
        ProcessInfo.processInfo.environment["CLAIDE_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }()

    var body: some View {
        VStack(spacing: 0) {
            TerminalTabBar(tabManager: tabManager) {
                tabManager.addTab(initialDirectory: Self.initialDirectory, fontFamily: fontFamily)
            }

            (tabManager.activeViewModel?.tabColor?.tint ?? Color(nsColor: TerminalTheme.background))
                .frame(height: 2)

            TerminalPanel(tabManager: tabManager, fontFamily: fontFamily)

            SessionStatusBar(status: sessionStatusVM.status)
        }
        .onAppear {
            tabManager.addTab(initialDirectory: Self.initialDirectory, fontFamily: fontFamily)
            let shellPid = pid_t(tabManager.activeTab?.terminalView.shellPid ?? 0)
            sessionStatusVM.startWatching(sessionDirectory: Self.initialDirectory, shellPid: shellPid)
        }
        .onChange(of: tabManager.activeViewModel?.currentDirectory) { _, newDir in
            if let dir = newDir.flatMap({ $0 }) {
                let shellPid = pid_t(tabManager.activeTab?.terminalView.shellPid ?? 0)
                sessionStatusVM.startWatching(sessionDirectory: dir, shellPid: shellPid)
            }
        }
        .onChange(of: cursorStyle) {
            tabManager.applyCursorStyleToAll()
        }
        .onChange(of: cursorBlink) {
            tabManager.applyCursorStyleToAll()
        }
        .onChange(of: schemeName) {
            tabManager.applyColorSchemeToAll()
        }
        .onChange(of: paneFocusIndicator) {
            tabManager.applyPaneFocusSettingsToAll()
        }
        .onChange(of: dimUnfocusedPanes) {
            tabManager.applyPaneFocusSettingsToAll()
        }
    }
}
