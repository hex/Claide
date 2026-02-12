// ABOUTME: A single row in the command palette results list with icon, title, and selection highlight.
// ABOUTME: Uses system accent color at reduced opacity for the selected state.

import SwiftUI

struct CommandPaletteRowView: View {
    let item: CommandPaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16, alignment: .center)

            Text(item.title)

            if let subtitle = item.subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }
}
