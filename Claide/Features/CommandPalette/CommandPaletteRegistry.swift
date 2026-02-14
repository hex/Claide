// ABOUTME: Builds the list of available command palette actions from the current tab manager state.
// ABOUTME: Provides tab switching, pane splitting, and tool window toggle commands.

import Foundation

@MainActor
enum CommandPaletteRegistry {

    static func buildActions(
        tabManager: TerminalTabManager,
        toggleSidebar: (@MainActor () -> Void)? = nil,
        layout: ToolWindowLayout? = nil
    ) -> [CommandPaletteItem] {
        var items: [CommandPaletteItem] = []

        items.append(CommandPaletteItem(
            id: "new-tab",
            title: "New Tab",
            icon: "plus.square",
            action: { @MainActor in tabManager.addTab() }
        ))

        items.append(CommandPaletteItem(
            id: "close-tab",
            title: "Close Tab",
            icon: "xmark.square",
            action: { @MainActor in tabManager.closeActiveTab() }
        ))

        items.append(CommandPaletteItem(
            id: "next-tab",
            title: "Next Tab",
            icon: "arrow.right.square",
            action: { @MainActor in
                guard let activeID = tabManager.activeTabID,
                      let index = tabManager.tabs.firstIndex(where: { $0.id == activeID }) else { return }
                let nextIndex = (index + 1) % tabManager.tabs.count
                tabManager.switchTo(id: tabManager.tabs[nextIndex].id)
            }
        ))

        items.append(CommandPaletteItem(
            id: "previous-tab",
            title: "Previous Tab",
            icon: "arrow.left.square",
            action: { @MainActor in
                guard let activeID = tabManager.activeTabID,
                      let index = tabManager.tabs.firstIndex(where: { $0.id == activeID }) else { return }
                let prevIndex = index > 0 ? index - 1 : tabManager.tabs.count - 1
                tabManager.switchTo(id: tabManager.tabs[prevIndex].id)
            }
        ))

        items.append(CommandPaletteItem(
            id: "split-horizontal",
            title: "Split Horizontally",
            icon: "rectangle.split.1x2",
            action: { @MainActor in tabManager.splitActivePane(axis: .horizontal) }
        ))

        items.append(CommandPaletteItem(
            id: "split-vertical",
            title: "Split Vertically",
            icon: "rectangle.split.2x1",
            action: { @MainActor in tabManager.splitActivePane(axis: .vertical) }
        ))

        items.append(CommandPaletteItem(
            id: "close-pane",
            title: "Close Pane",
            icon: "xmark.rectangle",
            action: { @MainActor in tabManager.closeActivePane() }
        ))

        if let toggleSidebar {
            items.append(CommandPaletteItem(
                id: "toggle-sidebar",
                title: "Toggle Right Panel",
                icon: "sidebar.right",
                action: toggleSidebar
            ))
        }

        // Tool window commands
        if let layout {
            items.append(CommandPaletteItem(
                id: "toggle-tasks",
                title: "Toggle Tasks",
                icon: "checklist",
                action: { @MainActor in layout.toggleWindow(.tasks) }
            ))

            items.append(CommandPaletteItem(
                id: "toggle-files",
                title: "Toggle Files",
                icon: "doc.text",
                action: { @MainActor in layout.toggleWindow(.files) }
            ))

            for edge in ToolWindowEdge.allCases {
                let title = "Toggle \(edge.rawValue.capitalized) Panel"
                items.append(CommandPaletteItem(
                    id: "toggle-\(edge.rawValue)-panel",
                    title: title,
                    icon: "sidebar.\(edge.rawValue)",
                    action: { @MainActor in layout.toggleEdge(edge) }
                ))
            }
        }

        // Per-tab switch commands
        for tab in tabManager.tabs {
            let tabID = tab.id
            let title = tab.viewModel.displayTitle
            items.append(CommandPaletteItem(
                id: "switch-tab-\(tabID.uuidString)",
                title: "Switch to: \(title)",
                subtitle: nil,
                icon: "terminal",
                action: { @MainActor in tabManager.switchTo(id: tabID) }
            ))
        }

        return items
    }
}
