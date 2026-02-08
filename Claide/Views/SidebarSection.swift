// ABOUTME: Right pane of the main split: collapsible board/graph and file log panels.
// ABOUTME: Each panel has a disclosure header for independent expand/collapse.

import SwiftUI

struct SidebarSection: View {
    let tabManager: TerminalTabManager
    @State private var graphVM = GraphViewModel()
    @State private var fileLogVM = FileLogViewModel()
    @State private var sidebarTab: SidebarTab = .board
    @AppStorage("fontFamily") private var fontFamily: String = ""
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"
    @AppStorage("tasksExpanded") private var tasksExpanded = true
    @AppStorage("filesExpanded") private var filesExpanded = true

    private static let initialDirectory: String = {
        ProcessInfo.processInfo.environment["CLAIDE_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }()

    enum SidebarTab: String, CaseIterable {
        case board = "Board"
        case graph = "Graph"
    }

    var body: some View {
        let _ = schemeName // Force SwiftUI to re-evaluate when the terminal scheme changes
        VStack(spacing: 0) {
            tasksSection
            filesSection
            Spacer(minLength: 0)
        }
        .padding(.top, 28)
        .overlay(alignment: .top) {
            WindowDragArea()
                .frame(height: 28)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundPrimary)
        .onAppear {
            if BeadsService.findBinary() == nil && ClaudeTaskService.isAvailable {
                graphVM.dataSource = .claudeCode
            }
            let vm = graphVM
            Task { @MainActor in
                await vm.loadIssues(workingDirectory: Self.initialDirectory)
            }
            let shellPid = pid_t(tabManager.activeTab?.terminalView.shellPid ?? 0)
            fileLogVM.startWatching(sessionDirectory: Self.initialDirectory, shellPid: shellPid)
        }
        .onChange(of: tabManager.activeViewModel?.currentDirectory) { _, newDir in
            if let dir = newDir.flatMap({ $0 }) {
                let vm = graphVM
                Task { @MainActor in
                    await vm.loadIssues(workingDirectory: dir)
                }
                let shellPid = pid_t(tabManager.activeTab?.terminalView.shellPid ?? 0)
                fileLogVM.startWatching(sessionDirectory: dir, shellPid: shellPid)
            }
        }
    }

    // MARK: - Tasks Section

    private var tasksSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Tasks", isExpanded: $tasksExpanded)

            if tasksExpanded {
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
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: tasksExpanded ? .infinity : nil)
    }

    // MARK: - Files Section

    private var filesSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Files", isExpanded: $filesExpanded)

            if filesExpanded {
                FileLogPanel(viewModel: fileLogVM)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: filesExpanded ? .infinity : nil)
    }

    // MARK: - Section Header

    private func sectionHeader<Trailing: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .frame(width: 12)

                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if isExpanded.wrappedValue {
                trailing()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Theme.backgroundSunken)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: Theme.borderWidth)
        }
    }

    private func sectionHeader(
        _ title: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        sectionHeader(title, isExpanded: isExpanded) { EmptyView() }
    }

    // MARK: - Tasks Header Controls

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
                    .frame(width: 20, height: 20)
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
                .frame(width: 20, height: 20)
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
                .frame(width: 20, height: 20)
                .background(sidebarTab == tab ? Theme.backgroundHover : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .overlay(Tooltip(tab.rawValue).allowsHitTesting(false))
    }

}
