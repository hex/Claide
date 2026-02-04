// ABOUTME: Horizontal tab bar for terminal tabs with add/close controls.
// ABOUTME: Active tab has top/left/right border and overlaps the bar's bottom border.

import SwiftUI

struct TerminalTabBar: View {
    let tabManager: TerminalTabManager
    let onAdd: () -> Void

    @State private var cmdHeld = false

    var body: some View {
        // ZStack instead of .background() to prevent safe area background propagation.
        // .background() modifiers auto-extend into the parent's safe area, causing
        // tab colors to bleed into the title bar area.
        ZStack {
            Theme.backgroundPrimary

            HStack(spacing: 0) {
                WindowDragArea()
                    .frame(width: 78)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: Theme.borderWidth)
                    }

                ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                    TabButton(
                        title: tab.viewModel.title,
                        isActive: tab.id == tabManager.activeTabID,
                        isRunning: tab.viewModel.isRunning,
                        canClose: tabManager.tabs.count > 1,
                        index: index + 1,
                        showIndex: cmdHeld,
                        onSelect: { tabManager.switchTo(id: tab.id) },
                        onClose: { tabManager.closeTab(id: tab.id) }
                    )
                }

                HStack {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .frame(maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: Theme.borderWidth)
                }
            }
            .padding(.trailing, Theme.panelPadding)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay { CmdKeyMonitor(isPressed: $cmdHeld).frame(width: 0, height: 0) }
    }
}

/// Monitors Cmd key press/release via NSEvent flags and updates a binding.
private struct CmdKeyMonitor: NSViewRepresentable {
    @Binding var isPressed: Bool

    func makeNSView(context: Context) -> CmdKeyView { CmdKeyView() }

    func updateNSView(_ nsView: CmdKeyView, context: Context) {
        nsView.onChange = { [self] held in isPressed = held }
    }

    final class CmdKeyView: NSView {
        nonisolated(unsafe) var onChange: ((Bool) -> Void)?
        private nonisolated(unsafe) var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            guard window != nil else { monitor = nil; return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.onChange?(event.modifierFlags.contains(.command))
                return event
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// Title bar drag region. Allows window dragging and double-click to zoom.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragAreaView { DragAreaView() }
    func updateNSView(_ nsView: DragAreaView, context: Context) {}

    final class DragAreaView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// Top, left, and right edges only — no bottom, so the active tab merges with content.
private struct TabBorder: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

private struct TabButton: View {
    let title: String
    let isActive: Bool
    let isRunning: Bool
    let canClose: Bool
    let index: Int
    let showIndex: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack {
            if isActive { Color(nsColor: TerminalTheme.background) }

            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isRunning ? Theme.accent : Theme.negative)
                        .frame(width: 5, height: 5)
                        .opacity(canClose && isHovered ? 0 : (showIndex && index <= 9 ? 0 : 1))

                    if canClose && isHovered && !(showIndex && index <= 9) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 14, height: 14)
                .overlay {
                    if showIndex && index <= 9 {
                        HStack(spacing: 2) {
                                Text("\u{2318}")
                                Text("\(index)")
                            }
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Theme.textMuted, lineWidth: 1)
                            )
                            .fixedSize()
                            .offset(x: -1.5)
                    }
                }

                Text(displayTitle)
                    .font(Theme.labelFont)
                    .foregroundStyle(isActive ? Theme.textPrimary : Theme.textMuted)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            if isActive {
                TabBorder()
                    .stroke(Theme.border, lineWidth: Theme.borderWidth)
            }
        }
        .overlay(alignment: .bottom) {
            if !isActive {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: Theme.borderWidth)
            }
        }
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
