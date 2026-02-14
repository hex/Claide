// ABOUTME: Panel container that shows the active tool window's content with a tabbed header.
// ABOUTME: Multiple windows on the same edge display as tabs; single window shows title + close.

import SwiftUI

struct ToolPanel<Content: View>: View {
    let edge: ToolWindowEdge
    @Bindable var layout: ToolWindowLayout
    @ViewBuilder let content: (ToolWindowID) -> Content

    var body: some View {
        if let activeID = layout.visibleWindow[edge] {
            let ids = layout.windows(on: edge)
            let size = layout.panelSize(for: edge)

            VStack(spacing: 0) {
                panelHeader(ids: ids, activeID: activeID)
                content(activeID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(
                width: edge.isVertical ? size : nil,
                height: edge.isVertical ? nil : size
            )
            .background(Theme.backgroundPrimary)
            .overlay(alignment: borderAlignment) {
                borderLine
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func panelHeader(ids: [ToolWindowID], activeID: ToolWindowID) -> some View {
        HStack(spacing: 0) {
            if ids.count > 1 {
                ForEach(ids, id: \.rawValue) { id in
                    panelTab(id: id, isActive: id == activeID)
                }
            } else if let desc = layout.descriptor(for: activeID) {
                HStack(spacing: 4) {
                    Image(systemName: desc.icon)
                        .font(.system(size: 9))
                    Text(desc.title)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            Button {
                layout.toggleEdge(edge)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .frame(height: 24)
        .background(Theme.backgroundSunken)
        .overlay(alignment: .bottom) {
            Theme.border.frame(height: Theme.borderWidth)
        }
    }

    @ViewBuilder
    private func panelTab(id: ToolWindowID, isActive: Bool) -> some View {
        if let desc = layout.descriptor(for: id) {
            Button {
                layout.toggleWindow(id)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: desc.icon)
                        .font(.system(size: 9))
                    Text(desc.title)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textMuted)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(isActive ? Theme.backgroundPrimary : .clear)
                .overlay(alignment: .trailing) {
                    Theme.border.frame(width: Theme.borderWidth)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Border

    private var borderAlignment: Alignment {
        switch edge {
        case .left: .trailing
        case .right: .leading
        case .bottom: .top
        }
    }

    @ViewBuilder
    private var borderLine: some View {
        if edge.isVertical {
            Theme.border.frame(width: Theme.borderWidth)
        } else {
            Theme.border.frame(height: Theme.borderWidth)
        }
    }
}
