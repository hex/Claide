// ABOUTME: Data model for a single command palette action with title, icon, and execution closure.
// ABOUTME: Used by CommandPaletteManager to populate and filter the command palette.

import Foundation

@MainActor
struct CommandPaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let action: @MainActor () -> Void

    init(id: String, title: String, subtitle: String? = nil, icon: String, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
    }
}
