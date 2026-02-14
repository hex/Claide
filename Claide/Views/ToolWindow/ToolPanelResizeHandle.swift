// ABOUTME: Draggable resize handle between a tool panel and the center terminal area.
// ABOUTME: Direction-aware: left panels grow rightward, right leftward, bottom upward.

import SwiftUI

struct ToolPanelResizeHandle: View {
    let edge: ToolWindowEdge
    @Bindable var layout: ToolWindowLayout

    @State private var dragStart: CGFloat?

    var body: some View {
        guard layout.isExpanded(edge) else { return AnyView(EmptyView()) }

        let handle: some View = Rectangle()
            .fill(Theme.border)
            .frame(
                width: edge.isVertical ? Theme.borderWidth : nil,
                height: edge.isVertical ? nil : Theme.borderWidth
            )
            .contentShape(Rectangle().inset(by: -2.5))
            .gesture(dragGesture)
            .onHover { hovering in
                if hovering {
                    (edge.isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }

        return AnyView(handle)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = layout.panelSize(for: edge)
                }
                guard let start = dragStart else { return }

                let delta: CGFloat
                switch edge {
                case .left:
                    delta = value.translation.width
                case .right:
                    delta = -value.translation.width
                case .bottom:
                    delta = -value.translation.height
                }

                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    layout.setPanelSize(start + delta, for: edge)
                }
            }
            .onEnded { _ in
                dragStart = nil
            }
    }
}
