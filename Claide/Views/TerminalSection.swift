// ABOUTME: Left pane of the main split: tab bar, terminal panel, and status bar.
// ABOUTME: Reads per-tab view models from TerminalTabManager for status display.

import SwiftUI

struct TerminalSection: View {
    let tabManager: TerminalTabManager
    var paletteManager: CommandPaletteManager?
    var showDragArea: Bool = true
    @AppStorage("fontFamily") private var fontFamily: String = ""
    // Cursor style is managed by Ghostty config (cursor-style, cursor-style-blink)
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"
    @AppStorage("paneFocusIndicator") private var paneFocusIndicator = true
    @AppStorage("dimUnfocusedPanes") private var dimUnfocusedPanes = true
    @AppStorage("statusBarStyle") private var statusBarStyle: String = "ambient"

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

            statusBar(status: tabManager.activeTab?.sessionStatusVM.status)
                .onTapGesture {
                    statusBarStyle = Self.nextStyle(after: statusBarStyle)
                }
        }
        .onAppear {
            if tabManager.tabs.isEmpty {
                tabManager.addTab(initialDirectory: Self.initialDirectory, fontFamily: fontFamily)
            }
        }
        .onChange(of: tabManager.activeViewModel?.currentDirectory) { _, newDir in
            if let dir = newDir ?? nil {
                tabManager.activeTab?.sessionStatusVM.startWatching(sessionDirectory: dir)
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

    private static let styles = ["ambient", "mission-control", "contextual", "classic"]

    private static func nextStyle(after current: String) -> String {
        guard let index = styles.firstIndex(of: current) else { return styles[0] }
        return styles[(index + 1) % styles.count]
    }

    @ViewBuilder
    private func statusBar(status: SessionStatus?) -> some View {
        if status != nil {
            switch statusBarStyle {
            case "mission-control":
                StatusBarMissionControl(status: status)
            case "contextual":
                StatusBarContextual(status: status)
            case "classic":
                SessionStatusBar(status: status)
            default:
                StatusBarAmbient(status: status)
            }
        } else {
            idleStatusBar
        }
    }

    private var idleStatusBar: some View {
        HStack {
            Text("idle")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.backgroundSunken)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: Theme.borderWidth)
        }
    }
}
