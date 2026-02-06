// ABOUTME: Horizontal tab bar for terminal tabs with add/close controls.
// ABOUTME: Active tab has top/left/right border and overlaps the bar's bottom border.

import SwiftUI
import AppKit

struct TerminalTabBar: View {
    let tabManager: TerminalTabManager
    let onAdd: () -> Void

    @State private var cmdHeld = false
    @State private var draggedTabID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var dragAccumulator: CGFloat = 0
    @State private var tabWidth: CGFloat = 0

    var body: some View {
        // ZStack instead of .background() to prevent safe area background propagation.
        // .background() modifiers auto-extend into the parent's safe area, causing
        // tab colors to bleed into the title bar area.
        ZStack {
            LinearGradient(
                colors: [Theme.backgroundSunken, Theme.backgroundPrimary],
                startPoint: .top,
                endPoint: .bottom
            )

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
                    let isActive = tab.id == tabManager.activeTabID
                    let isLast = index == tabManager.tabs.count - 1
                    let nextIsActive = !isLast && tabManager.tabs[index + 1].id == tabManager.activeTabID

                    TabButton(
                        title: tab.viewModel.displayTitle,
                        isActive: isActive,
                        isRunning: tab.viewModel.isRunning,
                        executablePath: tab.viewModel.executablePath,
                        tabColor: tab.viewModel.tabColor,
                        canClose: tabManager.tabs.count > 1,
                        showDivider: !isLast && !isActive && !nextIsActive,
                        index: index + 1,
                        showIndex: cmdHeld,
                        onSelect: { tabManager.switchTo(id: tab.id) },
                        onClose: { tabManager.closeTab(id: tab.id) },
                        onRename: { name in
                            let trimmed = name.trimmingCharacters(in: .whitespaces)
                            tab.viewModel.customTitle = trimmed.isEmpty ? nil : trimmed
                        },
                        onSetColor: { tab.viewModel.tabColor = $0 }
                    )
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: TabWidthKey.self, value: geo.size.width)
                        }
                    )
                    .offset(x: draggedTabID == tab.id ? dragOffset : 0)
                    .opacity(draggedTabID == tab.id ? 0.85 : 1)
                    .zIndex(draggedTabID == tab.id ? 1 : 0)
                    .shadow(color: draggedTabID == tab.id ? .black.opacity(0.4) : .clear, radius: 4, y: 2)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 5, coordinateSpace: .global)
                            .onChanged { value in
                                handleDragChanged(tabID: tab.id, translation: value.translation.width)
                            }
                            .onEnded { _ in handleDragEnded() }
                    )
                }

                AddTabButton(action: onAdd)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: Theme.borderWidth)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onPreferenceChange(TabWidthKey.self) { tabWidth = $0 }
        .overlay { CmdKeyMonitor(isPressed: $cmdHeld).frame(width: 0, height: 0) }
    }

    // MARK: - Drag Reorder

    private func handleDragChanged(tabID: UUID, translation: CGFloat) {
        if draggedTabID == nil {
            draggedTabID = tabID
            dragAccumulator = 0
        }
        dragOffset = translation - dragAccumulator

        guard tabWidth > 0,
              let sourceIndex = tabManager.tabs.firstIndex(where: { $0.id == tabID }) else { return }

        let threshold = tabWidth / 2

        if dragOffset > threshold, sourceIndex < tabManager.tabs.count - 1 {
            performMove(from: sourceIndex, to: sourceIndex + 1)
            dragAccumulator += tabWidth
            dragOffset = translation - dragAccumulator
        } else if dragOffset < -threshold, sourceIndex > 0 {
            performMove(from: sourceIndex, to: sourceIndex - 1)
            dragAccumulator -= tabWidth
            dragOffset = translation - dragAccumulator
        }
    }

    private func handleDragEnded() {
        dragAccumulator = 0
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            dragOffset = 0
            draggedTabID = nil
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                dragOffset = 0
                draggedTabID = nil
            }
        }
    }

    private func performMove(from source: Int, to destination: Int) {
        tabManager.moveTab(from: source, to: destination)
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

/// SF Symbol icon for the running process, tinted with a recognizable brand color.
private struct ProcessIcon: View {
    let path: String?
    let isRunning: Bool
    var colorOverride: Color?

    var body: some View {
        let info = Self.lookup(path)

        Image(systemName: info.symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(colorOverride ?? info.color)
            .frame(width: 16, height: 16)
            .opacity(isRunning ? 1.0 : 0.4)
    }

    private static func lookup(_ path: String?) -> (symbol: String, color: Color) {
        guard let path else { return ("questionmark.circle", .gray) }
        let command = (path as NSString).lastPathComponent

        if let match = iconMap[command] { return match }
        // Normalize: "python3.12" → "python", "Emacs-29" → "emacs"
        let normalized = command.lowercased().replacingOccurrences(
            of: #"[\d._-]+$"#, with: "", options: .regularExpression
        )
        if let match = iconMap[normalized] { return match }

        // Some tools use versioned paths (e.g. ~/.local/share/claude/versions/2.1.34).
        // Check parent directory names for a known command.
        let components = path.components(separatedBy: "/")
        for component in components.reversed().dropFirst() {
            let lower = component.lowercased()
            if let match = iconMap[lower] { return match }
        }

        return ("questionmark.circle", .gray)
    }

    private static let iconMap: [String: (symbol: String, color: Color)] = [
        // Shells
        "zsh":    ("apple.terminal.fill", Color(hex: 0xC5DB00)),
        "bash":   ("apple.terminal.fill", Color(hex: 0xF0F0F0)),
        "fish":   ("apple.terminal.fill", Color(hex: 0xD8494F)),
        "tcsh":   ("apple.terminal.fill", Color(hex: 0x88AACC)),
        "sh":     ("apple.terminal.fill", Color(hex: 0xAAAAAA)),
        // Editors
        "vim":    ("text.cursor",         Color(hex: 0x007F00)),
        "vi":     ("text.cursor",         Color(hex: 0x007F00)),
        "nvim":   ("text.cursor",         Color(hex: 0x54A23D)),
        "nano":   ("text.cursor",         Color(hex: 0xF0F0F0)),
        "emacs":  ("text.cursor",         Color(hex: 0x7E5CB7)),
        "pico":   ("text.cursor",         Color(hex: 0xAAAAAA)),
        // Languages & runtimes
        "python": ("chevron.left.forwardslash.chevron.right", Color(hex: 0xFFDF59)),
        "ruby":   ("chevron.left.forwardslash.chevron.right", Color(hex: 0xCC342D)),
        "irb":    ("chevron.left.forwardslash.chevron.right", Color(hex: 0xCC342D)),
        "node":   ("chevron.left.forwardslash.chevron.right", Color(hex: 0x7EBF00)),
        "perl":   ("chevron.left.forwardslash.chevron.right", Color(hex: 0x39457E)),
        "php":    ("chevron.left.forwardslash.chevron.right", Color(hex: 0x777BB3)),
        "java":   ("cup.and.saucer",                     Color(hex: 0xF89820)),
        "elixir": ("chevron.left.forwardslash.chevron.right", Color(hex: 0x440E60)),
        "erl":    ("chevron.left.forwardslash.chevron.right", Color(hex: 0x7F1831)),
        "go":     ("chevron.left.forwardslash.chevron.right", Color(hex: 0x00ADD8)),
        "cargo":  ("chevron.left.forwardslash.chevron.right", Color(hex: 0xDEA584)),
        "swift":  ("chevron.left.forwardslash.chevron.right", Color(hex: 0xF05138)),
        // Version control
        "git":    ("arrow.triangle.branch", Color(hex: 0xFC6D26)),
        // Package managers
        "npm":    ("shippingbox",     Color(hex: 0xC12127)),
        "npx":    ("shippingbox",     Color(hex: 0xC12127)),
        "yarn":   ("shippingbox",     Color(hex: 0x2C8EBB)),
        "pip":    ("shippingbox",     Color(hex: 0xFFDF59)),
        "brew":   ("shippingbox",     Color(hex: 0xFBB040)),
        "gem":    ("shippingbox",     Color(hex: 0xCC342D)),
        // Build tools
        "make":   ("hammer",          Color(hex: 0x00AEFF)),
        "gmake":  ("hammer",          Color(hex: 0x00AEFF)),
        "gcc":    ("hammer",          Color(hex: 0x00AEFF)),
        "clang":  ("hammer",          Color(hex: 0x00AEFF)),
        "cc":     ("hammer",          Color(hex: 0x00AEFF)),
        "xcodebuild": ("hammer",      Color(hex: 0x147EFB)),
        // Containers
        "docker": ("shippingbox",     Color(hex: 0x0EB7ED)),
        "docker-compose": ("shippingbox", Color(hex: 0x0EB7ED)),
        // Network
        "ssh":    ("lock",            Color(hex: 0x00AEFF)),
        "curl":   ("arrow.down.circle",    Color(hex: 0x9CCC65)),
        "wget":   ("arrow.down.circle",    Color(hex: 0x9CCC65)),
        "ping":   ("antenna.radiowaves.left.and.right", Color(hex: 0x00AEFF)),
        // Monitoring
        "top":    ("chart.bar",       Color(hex: 0x00AEFF)),
        "htop":   ("chart.bar",       Color(hex: 0x00AEFF)),
        // Search
        "grep":   ("magnifyingglass",      Color(hex: 0x9CCC65)),
        "rg":     ("magnifyingglass",      Color(hex: 0x9CCC65)),
        "find":   ("magnifyingglass",      Color(hex: 0x9CCC65)),
        "fd":     ("magnifyingglass",      Color(hex: 0x9CCC65)),
        // Files
        "less":   ("doc.text",             Color(hex: 0xAAAAAA)),
        "more":   ("doc.text",             Color(hex: 0xAAAAAA)),
        "cat":    ("doc.text",             Color(hex: 0xAAAAAA)),
        "tail":   ("doc.text",             Color(hex: 0xAAAAAA)),
        // Archive
        "tar":    ("doc.zipper",           Color(hex: 0xFD9126)),
        "zip":    ("doc.zipper",           Color(hex: 0xFD9126)),
        "unzip":  ("doc.zipper",           Color(hex: 0xFD9126)),
        "gzip":   ("doc.zipper",           Color(hex: 0xFD9126)),
        // AI
        "claude": ("brain",                Color(hex: 0xDA7756)),
    ]
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct TabWidthKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
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

private struct AddTabButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isHovered ? Theme.textPrimary : Theme.textMuted)
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Theme.backgroundHover : .clear)
        .onHover { isHovered = $0 }
    }
}

private struct TabButton: View {
    let title: String
    let isActive: Bool
    let isRunning: Bool
    let executablePath: String?
    let tabColor: TabColor?
    let canClose: Bool
    let showDivider: Bool
    let index: Int
    let showIndex: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onSetColor: (TabColor?) -> Void

    @State private var isHovered = false
    @State private var closeHovered = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var lastTapTime: Date = .distantPast
    @FocusState private var editFocused: Bool

    var body: some View {
        ZStack {
            if isActive {
                Color(nsColor: TerminalTheme.background)
            } else if isHovered {
                Theme.backgroundHover
            }

            if let tabColor {
                isActive ? tabColor.tint : tabColor.tint.opacity(0.6)
            }

            HStack(spacing: 6) {
                // Close button visible on hover; icon always present.
                // ZStack keeps the icon fixed while close button appears alongside.
                ZStack {
                    ProcessIcon(
                        path: executablePath,
                        isRunning: isRunning,
                        colorOverride: !isActive ? inactiveColor : nil
                    )
                    .opacity(showIndex && index <= 9 ? 0 : 1)

                    if index <= 9 {
                        Text("\(index)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 16, height: 16)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.backgroundPanel)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                            .opacity(showIndex ? 1 : 0)
                    }

                    if canClose && isHovered && !showIndex {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(closeHovered ? Theme.textPrimary : Theme.textMuted)
                                .frame(width: 16, height: 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(closeHovered ? Theme.backgroundHover : Theme.backgroundPanel)
                                )
                        }
                        .buttonStyle(.plain)
                        .onHover { closeHovered = $0 }
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: showIndex)

                if isEditing {
                    TextField("", text: $editText)
                        .font(Theme.labelFont)
                        .textFieldStyle(.plain)
                        .focused($editFocused)
                        .onSubmit { commitEdit() }
                        .onExitCommand { cancelEdit() }
                        .onKeyPress(.escape) { cancelEdit(); return .handled }
                } else {
                    Text(title)
                        .font(Theme.labelFont)
                        .foregroundStyle(isActive ? Theme.textPrimary : inactiveColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
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
        .overlay(alignment: .trailing) {
            if showDivider {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: Theme.borderWidth)
                    .padding(.vertical, 8)
            }
        }
        .contextMenu {
            Button("Rename...") { startEditing() }

            Menu("Tab Color") {
                ForEach(TabColor.allCases, id: \.self) { preset in
                    Toggle(isOn: Binding(
                        get: { tabColor == preset },
                        set: { _ in onSetColor(preset) }
                    )) {
                        Label {
                            Text(preset.label)
                        } icon: {
                            preset.swatch
                        }
                    }
                }

                Divider()

                Button("Clear") { onSetColor(nil) }
                    .disabled(tabColor == nil)
            }

            if canClose {
                Divider()
                Button("Close Tab") { onClose() }
            }
        }
        .onTapGesture {
            let now = Date()
            let isDoubleClick = now.timeIntervalSince(lastTapTime) < NSEvent.doubleClickInterval
            lastTapTime = now
            if isDoubleClick {
                startEditing()
            } else {
                onSelect()
            }
        }
        .onHover { isHovered = $0 }
    }

    private var inactiveColor: Color {
        if let tabColor, tabColor != .base { return tabColor.color.opacity(0.35) }
        return Theme.textMuted
    }

    private func startEditing() {
        editText = title
        isEditing = true
        editFocused = true
    }

    private func commitEdit() {
        isEditing = false
        onRename(editText)
    }

    private func cancelEdit() {
        isEditing = false
    }
}
