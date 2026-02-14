// ABOUTME: Tasks panel content for the tool window system: board/graph view with floating controls.
// ABOUTME: Extracted from SidebarSection to be hosted in any edge panel.

import SwiftUI

struct TasksToolContent: View {
    let tabManager: TerminalTabManager
    @Bindable var graphVM: GraphViewModel
    let hasTaskContext: Bool
    @State private var sidebarTab: SidebarTab = .board
    @AppStorage("fontFamily") private var fontFamily: String = ""

    enum SidebarTab: String, CaseIterable {
        case board = "Board"
        case graph = "Graph"
    }

    var body: some View {
        if hasTaskContext {
            ZStack(alignment: .bottomLeading) {
                switch sidebarTab {
                case .board:
                    KanbanPanel(viewModel: graphVM)
                case .graph:
                    GraphPanel(viewModel: graphVM, fontFamily: fontFamily)
                }

                floatingTabControls
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack {
                Spacer()
                Text("No task context")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Floating Controls

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

            Divider()
                .frame(height: 12)
                .padding(.horizontal, 2)

            dataSourceIcon(.beads, systemName: "circle.hexagongrid")
            dataSourceIcon(.claudeCode, systemName: "checklist")
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
