// ABOUTME: Left pane of the main split: tab bar, terminal panel, and status bar.
// ABOUTME: Owns session-scoped view models and wires terminal lifecycle events.

import SwiftUI

struct TerminalSection: View {
    let tabManager: TerminalTabManager
    var paletteManager: CommandPaletteManager?
    var showDragArea: Bool = true
    @State private var sessionStatusVM = SessionStatusViewModel()
    @AppStorage("fontFamily") private var fontFamily: String = ""
    // Cursor style is managed by Ghostty config (cursor-style, cursor-style-blink)
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"
    @AppStorage("paneFocusIndicator") private var paneFocusIndicator = true
    @AppStorage("dimUnfocusedPanes") private var dimUnfocusedPanes = true

    private static let initialDirectory: String = {
        ProcessInfo.processInfo.environment["CLAIDE_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }()

    var body: some View {
        VStack(spacing: 0) {
            TerminalTabBar(tabManager: tabManager, showDragArea: showDragArea) {
                tabManager.addTab(initialDirectory: Self.initialDirectory, fontFamily: fontFamily)
            }

            TerminalPanel(tabManager: tabManager, fontFamily: fontFamily)

            SessionStatusBar(status: sessionStatusVM.status)
        }
        .onAppear {
            if tabManager.tabs.isEmpty {
                tabManager.addTab(initialDirectory: Self.initialDirectory, fontFamily: fontFamily)
            }
            sessionStatusVM.startWatching(sessionDirectory: Self.initialDirectory)
        }
        .onChange(of: tabManager.activeViewModel?.currentDirectory) { _, newDir in
            if let dir = newDir ?? nil {
                sessionStatusVM.startWatching(sessionDirectory: dir)
            }
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
        .overlay {
            if let paletteManager, paletteManager.isPresented {
                CommandPaletteOverlayView(manager: paletteManager)
            }
        }
    }
}
