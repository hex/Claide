// ABOUTME: Right pane of the main split: collapsible board/graph and file log panels.
// ABOUTME: Each panel has a disclosure header for independent expand/collapse.

import SwiftUI
import AppKit

struct SidebarSection: View {
    let tabManager: TerminalTabManager
    @State private var graphVM = GraphViewModel()
    @State private var fileLogVM = FileLogViewModel()
    @State private var sidebarTab: SidebarTab = .board
    @AppStorage("fontFamily") private var fontFamily: String = ""
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"
    @AppStorage("tasksExpanded") private var tasksExpanded = true
    @AppStorage("filesExpanded") private var filesExpanded = true
    @AppStorage("sidebarSplitRatio") private var storedSplitRatio: Double = 0.5
    @State private var splitRatio: Double = 0.5
    @State private var dragStartRatio: Double?
    @State private var hasTaskContext = false

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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Match TerminalTabBar height so the sidebar content aligns
                // with the terminal panel below the tab bar.
                WindowDragArea()
                    .frame(height: 36)
                    .background(Theme.backgroundSunken)
                    .overlay(alignment: .bottom) {
                        Theme.border.frame(height: Theme.borderWidth)
                    }

                if hasTaskContext {
                    if tasksExpanded && filesExpanded {
                        // Headers stay outside the resizable area so they
                        // are always visible regardless of split position.
                        let contentHeight = geometry.size.height - 36 - 24 - 7 - 24
                        sectionHeader("Tasks", isExpanded: $tasksExpanded)
                        tasksContent
                            .frame(height: max(0, contentHeight * splitRatio))
                            .clipped()
                        sidebarDivider(totalHeight: max(1, contentHeight))
                        sectionHeader("Files", isExpanded: $filesExpanded)
                        filesContent
                            .frame(height: max(0, contentHeight * (1 - splitRatio)))
                            .clipped()
                    } else {
                        tasksSection
                        filesSection
                        Spacer(minLength: 0)
                    }
                } else {
                    filesSection
                    Spacer(minLength: 0)
                }
            }
            .frame(maxHeight: .infinity)
            .coordinateSpace(name: "sidebarContainer")
        }
        .background(Theme.backgroundPrimary)
        .onAppear {
            splitRatio = storedSplitRatio
            updateTaskContext(for: Self.initialDirectory)
            if hasTaskContext {
                if BeadsService.findBinary() == nil && ClaudeTaskService.isAvailable {
                    graphVM.dataSource = .claudeCode
                }
                let vm = graphVM
                Task { @MainActor in
                    await vm.loadIssues(workingDirectory: Self.initialDirectory)
                }
            }
            let shellPid = pid_t(tabManager.activeTab?.terminalView.shellPid ?? 0)
            fileLogVM.startWatching(sessionDirectory: Self.initialDirectory, shellPid: shellPid)
        }
        .onChange(of: tabManager.activeViewModel?.currentDirectory) { _, newDir in
            if let dir = newDir.flatMap({ $0 }) {
                updateTaskContext(for: dir)
                if hasTaskContext {
                    let vm = graphVM
                    Task { @MainActor in
                        await vm.loadIssues(workingDirectory: dir)
                    }
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
            if tasksExpanded { tasksContent }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: tasksExpanded ? .infinity : nil)
    }

    private var tasksContent: some View {
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

    // MARK: - Files Section

    private var filesSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Files", isExpanded: $filesExpanded)
            if filesExpanded { filesContent }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: filesExpanded ? .infinity : nil)
    }

    private var filesContent: some View {
        FileLogPanel(viewModel: fileLogVM)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Draggable Divider

    private func sidebarDivider(totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: Theme.borderWidth)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("sidebarContainer"))
                    .onChanged { value in
                        if dragStartRatio == nil { dragStartRatio = splitRatio }
                        let minRatio = 0.0
                        let maxRatio = 1.0
                        let delta = value.location.y - value.startLocation.y
                        let newRatio = dragStartRatio! + delta / totalHeight
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            splitRatio = min(max(newRatio, minRatio), maxRatio)
                        }
                    }
                    .onEnded { _ in
                        dragStartRatio = nil
                        storedSplitRatio = splitRatio
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    // MARK: - Section Header

    private func sectionHeader<Trailing: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                .frame(width: 12)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            if isExpanded.wrappedValue {
                trailing()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.wrappedValue.toggle()
            }
        }
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

    // MARK: - Task Context Detection

    private func updateTaskContext(for directory: String) {
        let hasBeads = BeadsService.findBinary() != nil
            && FileManager.default.fileExists(atPath: (directory as NSString).appendingPathComponent(".beads"))
        hasTaskContext = hasBeads || ClaudeTaskService.isAvailable
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
