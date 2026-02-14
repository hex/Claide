// ABOUTME: Manages command palette state: visibility, filtering, selection, and activation.
// ABOUTME: Bridges between the overlay UI and the tab manager's available actions.

import SwiftUI

@MainActor @Observable
final class CommandPaletteManager {

    var isPresented: Bool = false

    var query: String = "" {
        didSet { applyFilter() }
    }

    var selectedIndex: Int = 0
    private(set) var filteredItems: [CommandPaletteItem] = []
    private var allItems: [CommandPaletteItem] = []

    weak var tabManager: TerminalTabManager?
    var toggleSidebar: (@MainActor () -> Void)?

    func toggle() {
        if isPresented {
            dismiss()
        } else {
            refreshItems()
            query = ""
            selectedIndex = 0
            isPresented = true
        }
    }

    func dismiss() {
        isPresented = false
        query = ""
    }

    func moveSelection(_ direction: MoveCommandDirection) {
        guard !filteredItems.isEmpty else { return }
        switch direction {
        case .up:
            selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : filteredItems.count - 1
        case .down:
            selectedIndex = selectedIndex < filteredItems.count - 1 ? selectedIndex + 1 : 0
        default:
            break
        }
    }

    func activateSelected() {
        guard filteredItems.indices.contains(selectedIndex) else { return }
        let item = filteredItems[selectedIndex]
        dismiss()
        item.action()
    }

    func refreshItems() {
        guard let tabManager else { return }
        allItems = CommandPaletteRegistry.buildActions(
            tabManager: tabManager,
            toggleSidebar: toggleSidebar
        )
        applyFilter()
    }

    private func applyFilter() {
        if query.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter {
                $0.title.localizedCaseInsensitiveContains(query)
            }
        }
        selectedIndex = min(selectedIndex, max(filteredItems.count - 1, 0))
    }
}
