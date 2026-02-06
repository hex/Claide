// ABOUTME: Root layout with HSplitView: terminal on the left, sidebar on the right.
// ABOUTME: Sidebar has Board/Graph tabs on top, file change log always visible below.

import SwiftUI

struct ContentView: View {
    let tabManager: TerminalTabManager
    @State private var graphVM = GraphViewModel()
    @State private var fileLogVM = FileLogViewModel()
    @State private var sessionStatusVM = SessionStatusViewModel()
    @State private var sidebarTab: SidebarTab = .board
    @AppStorage("fontFamily") private var fontFamily: String = ""
    @AppStorage("cursorStyle") private var cursorStyle: String = "bar"
    @AppStorage("cursorBlink") private var cursorBlink: Bool = true

    /// Session directory the terminal opens to
    private let sessionDirectory: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".claude-sessions/claide")
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
            // Create the first tab and load sidebar data
            tabManager.addTab(initialDirectory: sessionDirectory, fontFamily: fontFamily)

            // Pick the best default data source
            if BeadsService.findBinary() == nil && ClaudeTaskService.isAvailable {
                graphVM.dataSource = .claudeCode
            }

            let vm = graphVM
            Task { @MainActor in
                await vm.loadIssues(workingDirectory: sessionDirectory)
            }
            let shellPid = pid_t(tabManager.activeTab?.terminalView.shellPid ?? 0)
            fileLogVM.startWatching(sessionDirectory: sessionDirectory, shellPid: shellPid)
            sessionStatusVM.startWatching(sessionDirectory: sessionDirectory, shellPid: shellPid)
        }
        .onChange(of: tabManager.activeViewModel?.currentDirectory) { _, newDir in
            if let dir = newDir.flatMap({ $0 }) {
                let vm = graphVM
                Task { @MainActor in
                    await vm.loadIssues(workingDirectory: dir)
                }
                let shellPid = pid_t(tabManager.activeTab?.terminalView.shellPid ?? 0)
                fileLogVM.startWatching(sessionDirectory: dir, shellPid: shellPid)
                sessionStatusVM.startWatching(sessionDirectory: dir, shellPid: shellPid)
            }
        }
        .onChange(of: cursorStyle) {
            tabManager.applyCursorStyleToAll()
        }
        .onChange(of: cursorBlink) {
            tabManager.applyCursorStyleToAll()
        }
    }

    // MARK: - Terminal

    private var terminalSection: some View {
        VStack(spacing: 0) {
            TerminalTabBar(tabManager: tabManager) {
                tabManager.addTab(initialDirectory: sessionDirectory, fontFamily: fontFamily)
            }

            // Colored strip between tab bar and terminal, matching the active tab's tint
            (tabManager.activeViewModel?.tabColor?.tint ?? Color(nsColor: TerminalTheme.background))
                .frame(height: 2)

            TerminalPanel(tabManager: tabManager, fontFamily: fontFamily)
                .padding(12)
                .background(Color(nsColor: TerminalTheme.background))

            SessionStatusBar(status: sessionStatusVM.status)
        }
    }

    // MARK: - Sidebar

    private var sidebarSection: some View {
        GeometryReader { geo in
        VSplitView {
            // Top: Board/Graph content with floating tab controls
            Group {
                switch sidebarTab {
                case .board:
                    KanbanPanel(viewModel: graphVM)
                case .graph:
                    GraphPanel(viewModel: graphVM, fontFamily: fontFamily)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                floatingTabControls
            }
            .frame(minHeight: 200)
            .background(SplitDividerSetter(ratio: 0.7))

            // Bottom: File changes (always visible)
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

    private var floatingTabControls: some View {
        HStack(spacing: 2) {
            tabIcon(.board, systemName: "rectangle.split.3x3")
            tabIcon(.graph, systemName: "point.3.connected.trianglepath.dotted")

            Divider()
                .frame(height: 12)
                .padding(.horizontal, 2)

            Button {
                let vm = graphVM
                let dir = tabManager.activeViewModel?.currentDirectory
                Task { @MainActor in await vm.loadIssues(workingDirectory: dir) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .overlay(Tooltip("Refresh").allowsHitTesting(false))

            if showDataSourceToggle {
                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 2)

                dataSourceIcon(.beads, systemName: "circle.hexagongrid")
                dataSourceIcon(.claudeCode, systemName: "checklist")
            }
        }
        .padding(3)
        .background(Theme.backgroundPanel.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.border, lineWidth: Theme.borderWidth)
        )
        .padding(8)
    }

    private var showDataSourceToggle: Bool { true }

    private func dataSourceIcon(_ source: DataSource, systemName: String) -> some View {
        Button {
            graphVM.dataSource = source
            let vm = graphVM
            let dir = tabManager.activeViewModel?.currentDirectory
            Task { @MainActor in await vm.loadIssues(workingDirectory: dir) }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10))
                .foregroundStyle(graphVM.dataSource == source ? Theme.textPrimary : Theme.textMuted)
                .frame(width: 22, height: 22)
                .background(graphVM.dataSource == source ? Theme.backgroundHover : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .overlay(Tooltip(source.rawValue).allowsHitTesting(false))
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
