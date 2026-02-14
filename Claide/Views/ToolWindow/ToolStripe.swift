// ABOUTME: Narrow button strip along a window edge showing icons for docked tool windows.
// ABOUTME: Left/right stripes use rotated text; bottom uses horizontal text. Supports drag-and-drop.

import SwiftUI

struct ToolStripe: View {
    let edge: ToolWindowEdge
    @Bindable var layout: ToolWindowLayout

    var body: some View {
        let ids = layout.windows(on: edge)
        if ids.isEmpty { return AnyView(EmptyView()) }

        let content = ForEach(ids, id: \.rawValue) { id in
            if let desc = layout.descriptor(for: id) {
                StripeButton(
                    descriptor: desc,
                    isActive: layout.visibleWindow[edge] == id,
                    edge: edge
                ) {
                    layout.toggleWindow(id)
                }
                .draggable(id)
            }
        }

        if edge.isVertical {
            return AnyView(
                VStack(spacing: 0) {
                    content
                    Spacer(minLength: 0)
                }
                .frame(width: 24)
                .background(Theme.backgroundSunken)
                .overlay(alignment: edge == .left ? .trailing : .leading) {
                    Theme.border.frame(width: Theme.borderWidth)
                }
                .dropDestination(for: ToolWindowID.self) { items, _ in
                    guard let id = items.first else { return false }
                    layout.moveWindow(id, to: edge)
                    return true
                }
            )
        } else {
            return AnyView(
                HStack(spacing: 0) {
                    content
                    Spacer(minLength: 0)
                }
                .frame(height: 24)
                .background(Theme.backgroundSunken)
                .overlay(alignment: .top) {
                    Theme.border.frame(height: Theme.borderWidth)
                }
                .dropDestination(for: ToolWindowID.self) { items, _ in
                    guard let id = items.first else { return false }
                    layout.moveWindow(id, to: edge)
                    return true
                }
            )
        }
    }
}

// MARK: - Stripe Button

private struct StripeButton: View {
    let descriptor: ToolWindowDescriptor
    let isActive: Bool
    let edge: ToolWindowEdge
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var label: some View {
        let content = HStack(spacing: 3) {
            Image(systemName: descriptor.icon)
                .font(.system(size: 9))
            Text(descriptor.title)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(isActive ? Theme.textPrimary : Theme.textMuted)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isActive ? Theme.backgroundHover : .clear)

        switch edge {
        case .left:
            content
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(width: 24)
                .padding(.vertical, 2)
        case .right:
            content
                .rotationEffect(.degrees(90))
                .fixedSize()
                .frame(width: 24)
                .padding(.vertical, 2)
        case .bottom:
            content
                .frame(height: 24)
        }
    }
}
