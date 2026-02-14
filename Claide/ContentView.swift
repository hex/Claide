// ABOUTME: Root layout with HSplitView: terminal on the left, sidebar on the right.
// ABOUTME: Sidebar has Board/Graph tabs on top, file change log always visible below.

import SwiftUI

struct ContentView: View {
    let tabManager: TerminalTabManager
    @State private var sidebarTab: SidebarTab = .board
    @AppStorage("fontFamily") private var fontFamily: String = ""
    // Cursor style is managed by Ghostty config (cursor-style, cursor-style-blink)

    /// Initial directory — from CLAIDE_DIR env var (for cs integration) or home.
    private static let initialDirectory: String = {
        ProcessInfo.processInfo.environment["CLAIDE_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }()

    enum SidebarTab: String, CaseIterable {
        case board = "Board"
        case graph = "Graph"
    }

    var body: some View {
        HSplitView {
            terminalSection
                .frame(minWidth: 400)
                .background(SplitDividerSetter(ratio: 0.7, vertical: true))

            sidebarSection
                .frame(minWidth: 280)
        }
        .background(Theme.backgroundPrimary)
        .onAppear {
            tabManager.addTab(initialDirectory: Self.initialDirectory, fontFamily: fontFamily)
        }
    }

    // MARK: - Terminal

    private var terminalSection: some View {
        VStack(spacing: 0) {
            TerminalTabBar(tabManager: tabManager) {
                tabManager.addTab(initialDirectory: Self.initialDirectory, fontFamily: fontFamily)
            }

            // Colored strip between tab bar and terminal, matching the active tab's tint
            (tabManager.activeViewModel?.tabColor?.tint ?? Color(nsColor: TerminalTheme.background))
                .frame(height: 2)

            TerminalPanel(tabManager: tabManager, fontFamily: fontFamily)

            SessionStatusBar(status: tabManager.activeTab?.sessionStatusVM.status)
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarSection: some View {
        if let graphVM = tabManager.activeTab?.graphVM,
           let fileLogVM = tabManager.activeTab?.fileLogVM {
            GeometryReader { geo in
                VSplitView {
                    Group {
                        switch sidebarTab {
                        case .board:
                            KanbanPanel(viewModel: graphVM)
                        case .graph:
                            GraphPanel(viewModel: graphVM, fontFamily: fontFamily)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 200)
                    .background(SplitDividerSetter(ratio: 0.7))

                    VStack(spacing: 0) {
                        FileLogPanel(viewModel: fileLogVM)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(minHeight: 80)
                }
                .padding(.top, 28)
                .background(Theme.backgroundPrimary)
            }
        }
    }

    private func tabIcon(_ tab: SidebarTab, systemName: String) -> some View {
        Button {
            sidebarTab = tab
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10))
                .foregroundStyle(sidebarTab == tab ? Theme.textPrimary : Theme.textMuted)
                .frame(width: 22, height: 22)
                .background(sidebarTab == tab ? Theme.backgroundHover : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .overlay(Tooltip(tab.rawValue).allowsHitTesting(false))
    }

}
