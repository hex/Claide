// ABOUTME: Horizontal tab bar for terminal tabs with add/close controls.
// ABOUTME: Matches the existing status bar style (monospaced, uppercase, muted text).

import SwiftUI

struct TerminalTabBar: View {
    let tabManager: TerminalTabManager
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabManager.tabs) { tab in
                TabButton(
                    title: tab.viewModel.title,
                    isActive: tab.id == tabManager.activeTabID,
                    isRunning: tab.viewModel.isRunning,
                    canClose: tabManager.tabs.count > 1,
                    onSelect: { tabManager.switchTo(id: tab.id) },
                    onClose: { tabManager.closeTab(id: tab.id) }
                )
            }

            // Add tab button
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, Theme.panelPadding)
        .background(Theme.backgroundPanel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: Theme.borderWidth)
        }
    }
}

private struct TabButton: View {
    let title: String
    let isActive: Bool
    let isRunning: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isRunning ? Theme.accent : Theme.negative)
                    .frame(width: 5, height: 5)
                    .opacity(canClose && isHovered ? 0 : 1)

                if canClose && isHovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 14, height: 14)

            Text(displayTitle)
                .font(Theme.labelFont)
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textMuted)
                .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(isActive ? Theme.backgroundHover : .clear)
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
    }

    private var displayTitle: String {
        let t = title
        if t.count > 20 {
            return String(t.prefix(18)) + "..."
        }
        return t
    }
}
