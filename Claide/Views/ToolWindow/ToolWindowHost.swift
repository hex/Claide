// ABOUTME: Top-level SwiftUI view for the main window with dockable tool panels on any edge.
// ABOUTME: Manages the center terminal area surrounded by stripes, panels, and resize handles.

import SwiftUI

struct ToolWindowHost: View {
    let tabManager: TerminalTabManager
    let paletteManager: CommandPaletteManager
    @Bindable var layout: ToolWindowLayout
    let commandKeyObserver: CommandKeyObserver

    @State private var graphVM = GraphViewModel()
    @State private var fileLogVM = FileLogViewModel()

    private static let initialDirectory: String = {
        ProcessInfo.processInfo.environment["CLAIDE_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }()

    var body: some View {
        HStack(spacing: 0) {
            // Left stripe
            if layout.hasWindows(on: .left) {
                ToolStripe(edge: .left, layout: layout)
            }

            // Left panel + resize handle
            ToolPanel(edge: .left, layout: layout, content: panelContent)
            if layout.isExpanded(.left) {
                ToolPanelResizeHandle(edge: .left, layout: layout)
            }

            // Center column: terminal + bottom panel
            VStack(spacing: 0) {
                TerminalSection(tabManager: tabManager, paletteManager: paletteManager, showDragArea: true)
                    .environment(commandKeyObserver)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom resize handle + panel + stripe
                if layout.isExpanded(.bottom) {
                    ToolPanelResizeHandle(edge: .bottom, layout: layout)
                }
                ToolPanel(edge: .bottom, layout: layout, content: panelContent)
                if layout.hasWindows(on: .bottom) {
                    ToolStripe(edge: .bottom, layout: layout)
                }
            }

            // Right resize handle + panel
            if layout.isExpanded(.right) {
                ToolPanelResizeHandle(edge: .right, layout: layout)
            }
            ToolPanel(edge: .right, layout: layout, content: panelContent)

            // Right stripe
            if layout.hasWindows(on: .right) {
                ToolStripe(edge: .right, layout: layout)
            }
        }
        .background(Theme.backgroundPrimary)
        .onAppear {
            let dir = Self.initialDirectory
            updateTaskContext(for: dir)
            if hasTaskContext {
                if BeadsService.findBinary() == nil && ClaudeTaskService.isAvailable {
                    graphVM.dataSource = .claudeCode
                }
                let vm = graphVM
                Task { @MainActor in
                    await vm.loadIssues(workingDirectory: dir)
                }
            }
            fileLogVM.startWatching(sessionDirectory: dir)
        }
        .onChange(of: tabManager.activeViewModel?.currentDirectory) { _, newDir in
            if let dir = newDir ?? nil {
                updateTaskContext(for: dir)
                if hasTaskContext {
                    let vm = graphVM
                    Task { @MainActor in
                        await vm.loadIssues(workingDirectory: dir)
                    }
                }
                fileLogVM.startWatching(sessionDirectory: dir)
            }
        }
    }

    // MARK: - Panel Content

    @ViewBuilder
    private func panelContent(for id: ToolWindowID) -> some View {
        switch id {
        case .tasks:
            TasksToolContent(
                tabManager: tabManager,
                graphVM: graphVM,
                hasTaskContext: hasTaskContext
            )
        case .files:
            FilesToolContent(viewModel: fileLogVM)
        default:
            Text("Unknown panel")
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Task Context Detection

    @State private var hasTaskContext = false

    private func updateTaskContext(for directory: String) {
        let hasBeads = BeadsService.findBinary() != nil
            && FileManager.default.fileExists(atPath: (directory as NSString).appendingPathComponent(".beads"))
        hasTaskContext = hasBeads || ClaudeTaskService.isAvailable
    }
}
