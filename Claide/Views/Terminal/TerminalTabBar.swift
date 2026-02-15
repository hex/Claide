// ABOUTME: Horizontal tab bar for terminal tabs with add/close controls.
// ABOUTME: Active tab has no bottom border; inactive tabs and empty areas show the border line.

import SwiftUI
import AppKit

struct TerminalTabBar: View {
    let tabManager: TerminalTabManager
    var showDragArea: Bool = true
    let onAdd: () -> Void

    @Environment(CommandKeyObserver.self) private var cmdKeyObserver
    @State private var draggedTabID: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var dragAccumulator: CGFloat = 0
    @State private var windowDragStartOrigin: NSPoint?
    @State private var windowDragStartMouse: NSPoint?
    @State private var containerWidth: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    private var effectiveTabWidth: CGFloat {
        let count = CGFloat(tabManager.tabs.count)
        guard containerWidth > 0, count > 0 else { return TerminalTabBarMetrics.tabMaxWidth }
        return min(
            TerminalTabBarMetrics.tabMaxWidth,
            max(TerminalTabBarMetrics.tabMinWidth, containerWidth / count)
        )
    }

    private var canScrollLeft: Bool { scrollOffset > 1 }
    private var canScrollRight: Bool {
        contentWidth > containerWidth && scrollOffset < contentWidth - containerWidth - 1
    }

    var body: some View {
        let singleTab = tabManager.tabs.count == 1

        VStack(spacing: 0) {
        // ZStack instead of .background() to prevent safe area background propagation.
        // .background() modifiers auto-extend into the parent's safe area, causing
        // tab colors to bleed into the title bar area.
        ZStack {
            Theme.backgroundSunken

            HStack(spacing: 0) {
                if showDragArea {
                    WindowDragArea()
                        .frame(width: 110)
                        .frame(maxHeight: .infinity)
                        .overlay {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: 76)
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Theme.textMuted.opacity(0.5))
                                    .frame(maxWidth: .infinity)
                            }
                            .allowsHitTesting(false)
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Theme.border)
                                .frame(height: Theme.borderWidth)
                        }
                }

                ScrollViewReader { scrollReader in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                                let isActive = tab.id == tabManager.activeTabID
                                let isLast = index == tabManager.tabs.count - 1
                                let nextIsActive = !isLast && tabManager.tabs[index + 1].id == tabManager.activeTabID

                                TabButton(
                                    tabId: tab.id,
                                    title: tab.viewModel.displayTitle,
                                    isActive: isActive,
                                    isRunning: tab.viewModel.isRunning,
                                    isTmuxPane: tab.viewModel.isTmuxPane,
                                    executablePath: tab.viewModel.executablePath,
                                    tabColor: tab.viewModel.tabColor,
                                    paneCount: tab.paneController.paneTree.paneCount,
                                    tabCount: tabManager.tabs.count,
                                    isLastTab: isLast,
                                    showDivider: !isLast && !isActive && !nextIsActive,
                                    index: index + 1,
                                    showIndex: cmdKeyObserver.isPressed,
                                    onSelect: { tabManager.switchTo(id: tab.id) },
                                    onClose: { tabManager.closeTab(id: tab.id) },
                                    onRename: { name in
                                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                                        tab.viewModel.customTitle = trimmed.isEmpty ? nil : trimmed
                                    },
                                    onSetColor: { tab.viewModel.tabColor = $0 },
                                    onCloseOthers: { tabManager.closeOthersKeeping(id: tab.id) },
                                    onCloseToRight: { tabManager.closeToRight(afterId: tab.id) },
                                    onCloseAll: {
                                        tabManager.closeAll()
                                        onAdd()
                                    }
                                )
                                .frame(width: effectiveTabWidth)
                                .id(tab.id)
                                .offset(x: draggedTabID == tab.id ? dragOffset : 0)
                                .opacity(draggedTabID == tab.id ? 0.85 : 1)
                                .zIndex(draggedTabID == tab.id ? 1 : 0)
                                .shadow(color: draggedTabID == tab.id ? .black.opacity(0.4) : .clear, radius: 4, y: 2)
                                .simultaneousGesture(
                                    singleTab ? nil : DragGesture(minimumDistance: 5, coordinateSpace: .global)
                                        .onChanged { value in
                                            handleDragChanged(tabID: tab.id, translation: value.translation.width)
                                        }
                                        .onEnded { _ in handleDragEnded() }
                                )
                                .highPriorityGesture(
                                    singleTab ? DragGesture(minimumDistance: 5, coordinateSpace: .global)
                                        .onChanged { _ in handleWindowDrag() }
                                        .onEnded { _ in
                                            windowDragStartOrigin = nil
                                            windowDragStartMouse = nil
                                        } : nil
                                )
                            }
                        }
                        .background(
                            GeometryReader { contentGeo in
                                Color.clear
                                    .onChange(of: contentGeo.frame(in: .named("tabScroll"))) { _, newFrame in
                                        scrollOffset = -newFrame.minX
                                        contentWidth = newFrame.width
                                    }
                                    .onAppear {
                                        let frame = contentGeo.frame(in: .named("tabScroll"))
                                        scrollOffset = -frame.minX
                                        contentWidth = frame.width
                                    }
                            }
                        )
                    }
                    .coordinateSpace(name: "tabScroll")
                    .onChange(of: tabManager.activeTabID) { _, newID in
                        if let id = newID {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                scrollReader.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { containerWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, newWidth in containerWidth = newWidth }
                    }
                )
                .background(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: Theme.borderWidth)
                }
                .overlay(alignment: .leading) {
                    TerminalTabsOverflowShadow(
                        width: TerminalTabBarMetrics.overflowShadowWidth,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .padding(.top, 1)
                    .padding(.bottom, 1)
                    .opacity(canScrollLeft ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: canScrollLeft)
                }
                .overlay(alignment: .trailing) {
                    TerminalTabsOverflowShadow(
                        width: TerminalTabBarMetrics.overflowShadowWidth,
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                    .padding(.top, 1)
                    .padding(.bottom, 1)
                    .opacity(canScrollRight ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: canScrollRight)
                }
                if singleTab {
                    WindowDragArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Theme.border)
                                .frame(height: Theme.borderWidth)
                        }
                }

                AddTabButton(action: onAdd)
            }
        }
        .fixedSize(horizontal: false, vertical: true)

        (tabManager.activeTab?.viewModel.tabColor?.tint ?? Color(nsColor: TerminalTheme.background))
            .frame(height: 2)
        }
    }

    // MARK: - Drag Reorder

    private func handleWindowDrag() {
        guard let window = NSApp.keyWindow else { return }
        if windowDragStartOrigin == nil {
            windowDragStartOrigin = window.frame.origin
            windowDragStartMouse = NSEvent.mouseLocation
        }
        guard let startOrigin = windowDragStartOrigin,
              let startMouse = windowDragStartMouse else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: startOrigin.x + (current.x - startMouse.x),
            y: startOrigin.y + (current.y - startMouse.y)
        ))
    }

    private func handleDragChanged(tabID: UUID, translation: CGFloat) {
        if draggedTabID == nil {
            draggedTabID = tabID
            dragAccumulator = 0
        }
        dragOffset = translation - dragAccumulator

        let tw = effectiveTabWidth
        guard tw > 0,
              let sourceIndex = tabManager.tabs.firstIndex(where: { $0.id == tabID }) else { return }

        let threshold = tw / 2

        if dragOffset > threshold, sourceIndex < tabManager.tabs.count - 1 {
            performMove(from: sourceIndex, to: sourceIndex + 1)
            dragAccumulator += tw
            dragOffset = translation - dragAccumulator
        } else if dragOffset < -threshold, sourceIndex > 0 {
            performMove(from: sourceIndex, to: sourceIndex - 1)
            dragAccumulator -= tw
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

/// Title bar drag region. Allows window dragging and double-click to zoom.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragAreaView { DragAreaView() }
    func updateNSView(_ nsView: DragAreaView, context: Context) {}

    final class DragAreaView: NSView {
        /// Saved frame before zoom so double-click can toggle back.
        private var preZoomFrame: NSRect?

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                // Non-animated frame change — zoom(nil) hangs during the animated
                // resize with Ghostty's Metal layer-hosting view.
                guard let window, let screen = window.screen else { return }
                let visibleFrame = screen.visibleFrame
                if window.frame == visibleFrame, let saved = preZoomFrame {
                    window.setFrame(saved, display: true)
                    preZoomFrame = nil
                } else {
                    preZoomFrame = window.frame
                    window.setFrame(visibleFrame, display: true)
                }
                return
            }

            guard let window else { return }
            let startOrigin = window.frame.origin
            let startMouse = NSEvent.mouseLocation

            NSCursor.closedHand.push()

            while true {
                guard let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
                if next.type == .leftMouseUp { break }

                let current = NSEvent.mouseLocation
                window.setFrameOrigin(NSPoint(
                    x: startOrigin.x + (current.x - startMouse.x),
                    y: startOrigin.y + (current.y - startMouse.y)
                ))
            }

            NSCursor.pop()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// Captures middle mouse button clicks. SwiftUI has no native middle-click gesture.
/// Uses an event monitor instead of overriding otherMouseDown so the NSView can
/// remain invisible to hit-testing — otherwise the overlay blocks left-click events
/// from reaching SwiftUI's gesture system (close button, tap-to-select, rename).
private struct MiddleClickHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> View {
        let v = View()
        v.action = action
        return v
    }

    func updateNSView(_ nsView: View, context: Context) {
        nsView.action = action
    }

    final class View: NSView {
        nonisolated(unsafe) var action: (() -> Void)?
        private nonisolated(unsafe) var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            guard window != nil else { monitor = nil; return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
                guard let self,
                      event.buttonNumber == 2,
                      let window = self.window,
                      event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    self.action?()
                }
                return event
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// SF Symbol icon for the running process, tinted with a recognizable brand color.
private struct ProcessIcon: View {
    let path: String?
    var colorOverride: Color?

    private enum IconSource {
        case sfSymbol(String, Color)
        case appIcon(NSImage)
    }

    var body: some View {
        switch Self.lookup(path) {
        case .sfSymbol(let symbol, let color):
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colorOverride ?? color)
                .frame(width: 16, height: 16)        case .appIcon(let nsImage):
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)        }
    }

    private static func lookup(_ path: String?) -> IconSource {
        guard let path else { return .sfSymbol("gearshape", .gray) }
        let command = (path as NSString).lastPathComponent

        if let match = iconMap[command] { return .sfSymbol(match.0, match.1) }
        // Normalize: "python3.12" → "python", "Emacs-29" → "emacs"
        let normalized = command.lowercased().replacingOccurrences(
            of: #"[\d._-]+$"#, with: "", options: .regularExpression
        )
        if let match = iconMap[normalized] { return .sfSymbol(match.0, match.1) }

        // Some tools use versioned paths (e.g. ~/.local/share/claude/versions/2.1.34).
        // Check parent directory names for a known command.
        let components = path.components(separatedBy: "/")
        for component in components.reversed().dropFirst() {
            let lower = component.lowercased()
            if let match = iconMap[lower] { return .sfSymbol(match.0, match.1) }
        }

        // GUI apps inside .app bundles get their real icon.
        if let appPath = appBundlePath(for: path) {
            return .appIcon(NSWorkspace.shared.icon(forFile: appPath))
        }

        return .sfSymbol("gearshape", .gray)
    }

    /// Extracts the .app bundle path from an executable path.
    /// e.g. "/Applications/Safari.app/Contents/MacOS/Safari" → "/Applications/Safari.app"
    private static func appBundlePath(for executablePath: String) -> String? {
        let components = executablePath.components(separatedBy: "/")
        for (i, component) in components.enumerated() {
            if component.hasSuffix(".app") {
                return components[0...i].joined(separator: "/")
            }
        }
        return nil
    }

    private static let iconMap: [String: (symbol: String, color: Color)] = [
        // Shells
        "zsh":        ("apple.terminal.fill", Color(hex: 0xC5DB00)),
        "bash":       ("apple.terminal.fill", Color(hex: 0xF0F0F0)),
        "fish":       ("apple.terminal.fill", Color(hex: 0xD8494F)),
        "tcsh":       ("apple.terminal.fill", Color(hex: 0x88AACC)),
        "sh":         ("apple.terminal.fill", Color(hex: 0xAAAAAA)),
        // Editors
        "vim":        ("text.cursor",         Color(hex: 0x007F00)),
        "vi":         ("text.cursor",         Color(hex: 0x007F00)),
        "nvim":       ("text.cursor",         Color(hex: 0x54A23D)),
        "nano":       ("text.cursor",         Color(hex: 0xF0F0F0)),
        "emacs":      ("text.cursor",         Color(hex: 0x7E5CB7)),
        "pico":       ("text.cursor",         Color(hex: 0xAAAAAA)),
        "hx":         ("text.cursor",         Color(hex: 0xBDB0F0)),
        "helix":      ("text.cursor",         Color(hex: 0xBDB0F0)),
        "micro":      ("text.cursor",         Color(hex: 0xF0F0F0)),
        "code":       ("text.cursor",         Color(hex: 0x007ACC)),
        // Languages & runtimes
        "python":     ("chevron.left.forwardslash.chevron.right", Color(hex: 0xFFDF59)),
        "ruby":       ("chevron.left.forwardslash.chevron.right", Color(hex: 0xCC342D)),
        "irb":        ("chevron.left.forwardslash.chevron.right", Color(hex: 0xCC342D)),
        "node":       ("chevron.left.forwardslash.chevron.right", Color(hex: 0x7EBF00)),
        "deno":       ("chevron.left.forwardslash.chevron.right", Color(hex: 0x01CA75)),
        "bun":        ("chevron.left.forwardslash.chevron.right", Color(hex: 0xFBECDB)),
        "perl":       ("chevron.left.forwardslash.chevron.right", Color(hex: 0x39457E)),
        "php":        ("chevron.left.forwardslash.chevron.right", Color(hex: 0x777BB3)),
        "java":       ("cup.and.saucer",       Color(hex: 0xF89820)),
        "elixir":     ("chevron.left.forwardslash.chevron.right", Color(hex: 0x440E60)),
        "erl":        ("chevron.left.forwardslash.chevron.right", Color(hex: 0x7F1831)),
        "go":         ("chevron.left.forwardslash.chevron.right", Color(hex: 0x00ADD8)),
        "cargo":      ("chevron.left.forwardslash.chevron.right", Color(hex: 0xDEA584)),
        "rustc":      ("chevron.left.forwardslash.chevron.right", Color(hex: 0xDEA584)),
        "rustup":     ("chevron.left.forwardslash.chevron.right", Color(hex: 0xDEA584)),
        "swift":      ("chevron.left.forwardslash.chevron.right", Color(hex: 0xF05138)),
        "zig":        ("chevron.left.forwardslash.chevron.right", Color(hex: 0xF7A41D)),
        "tsc":        ("chevron.left.forwardslash.chevron.right", Color(hex: 0x3178C6)),
        "lua":        ("chevron.left.forwardslash.chevron.right", Color(hex: 0x000080)),
        "luajit":     ("chevron.left.forwardslash.chevron.right", Color(hex: 0x000080)),
        "R":          ("chevron.left.forwardslash.chevron.right", Color(hex: 0x276DC3)),
        "Rscript":    ("chevron.left.forwardslash.chevron.right", Color(hex: 0x276DC3)),
        "julia":      ("chevron.left.forwardslash.chevron.right", Color(hex: 0x9558B2)),
        "ghc":        ("chevron.left.forwardslash.chevron.right", Color(hex: 0x5E5086)),
        "ghci":       ("chevron.left.forwardslash.chevron.right", Color(hex: 0x5E5086)),
        "scala":      ("chevron.left.forwardslash.chevron.right", Color(hex: 0xDC322F)),
        "kotlin":     ("chevron.left.forwardslash.chevron.right", Color(hex: 0x7F52FF)),
        "kotlinc":    ("chevron.left.forwardslash.chevron.right", Color(hex: 0x7F52FF)),
        "dotnet":     ("chevron.left.forwardslash.chevron.right", Color(hex: 0x512BD4)),
        "csc":        ("chevron.left.forwardslash.chevron.right", Color(hex: 0x512BD4)),
        // Version control
        "git":        ("arrow.triangle.branch", Color(hex: 0xFC6D26)),
        "tig":        ("arrow.triangle.branch", Color(hex: 0xFC6D26)),
        "gh":         ("arrow.triangle.branch", Color(hex: 0xF0F0F0)),
        "lazygit":    ("arrow.triangle.branch", Color(hex: 0xFC6D26)),
        // Package managers
        "npm":        ("shippingbox",     Color(hex: 0xC12127)),
        "npx":        ("shippingbox",     Color(hex: 0xC12127)),
        "pnpm":       ("shippingbox",     Color(hex: 0xF69220)),
        "yarn":       ("shippingbox",     Color(hex: 0x2C8EBB)),
        "pip":        ("shippingbox",     Color(hex: 0xFFDF59)),
        "pipx":       ("shippingbox",     Color(hex: 0xFFDF59)),
        "uv":         ("shippingbox",     Color(hex: 0xDE5FE9)),
        "conda":      ("shippingbox",     Color(hex: 0x44A833)),
        "mamba":      ("shippingbox",     Color(hex: 0x44A833)),
        "brew":       ("shippingbox",     Color(hex: 0xFBB040)),
        "gem":        ("shippingbox",     Color(hex: 0xCC342D)),
        "bundle":     ("shippingbox",     Color(hex: 0xCC342D)),
        "pod":        ("shippingbox",     Color(hex: 0xEE3322)),
        "composer":   ("shippingbox",     Color(hex: 0x885630)),
        // Build tools
        "make":       ("hammer",          Color(hex: 0x00AEFF)),
        "gmake":      ("hammer",          Color(hex: 0x00AEFF)),
        "gcc":        ("hammer",          Color(hex: 0x00AEFF)),
        "clang":      ("hammer",          Color(hex: 0x00AEFF)),
        "cc":         ("hammer",          Color(hex: 0x00AEFF)),
        "xcodebuild": ("hammer",          Color(hex: 0x147EFB)),
        "cmake":      ("hammer",          Color(hex: 0x00AEFF)),
        "ninja":      ("hammer",          Color(hex: 0x00AEFF)),
        "gradle":     ("hammer",          Color(hex: 0x1BA8CB)),
        "mvn":        ("hammer",          Color(hex: 0xC71A36)),
        // Containers
        "docker":     ("shippingbox",     Color(hex: 0x0EB7ED)),
        "docker-compose": ("shippingbox", Color(hex: 0x0EB7ED)),
        "podman":     ("shippingbox",     Color(hex: 0x892CA0)),
        // Infrastructure
        "kubectl":    ("cloud",           Color(hex: 0x326CE5)),
        "helm":       ("cloud",           Color(hex: 0x0F1689)),
        "terraform":  ("cloud",           Color(hex: 0x844FBA)),
        "tf":         ("cloud",           Color(hex: 0x844FBA)),
        "ansible":    ("cloud",           Color(hex: 0xEE0000)),
        "vagrant":    ("cloud",           Color(hex: 0x1868F2)),
        "aws":        ("cloud",           Color(hex: 0xFF9900)),
        "gcloud":     ("cloud",           Color(hex: 0x4285F4)),
        "az":         ("cloud",           Color(hex: 0x0078D4)),
        // Network
        "ssh":        ("lock",            Color(hex: 0x00AEFF)),
        "scp":        ("lock",            Color(hex: 0x00AEFF)),
        "sftp":       ("lock",            Color(hex: 0x00AEFF)),
        "curl":       ("arrow.down.circle",    Color(hex: 0x9CCC65)),
        "wget":       ("arrow.down.circle",    Color(hex: 0x9CCC65)),
        "ping":       ("antenna.radiowaves.left.and.right", Color(hex: 0x00AEFF)),
        "traceroute": ("antenna.radiowaves.left.and.right", Color(hex: 0x00AEFF)),
        "mtr":        ("antenna.radiowaves.left.and.right", Color(hex: 0x00AEFF)),
        "nc":         ("network",         Color(hex: 0x00AEFF)),
        "netcat":     ("network",         Color(hex: 0x00AEFF)),
        "nmap":       ("network",         Color(hex: 0x00AEFF)),
        "dig":        ("network",         Color(hex: 0x00AEFF)),
        "nslookup":   ("network",         Color(hex: 0x00AEFF)),
        "telnet":     ("network",         Color(hex: 0x00AEFF)),
        "rsync":      ("arrow.left.arrow.right", Color(hex: 0x9CCC65)),
        // Database
        "psql":       ("cylinder",        Color(hex: 0x336791)),
        "mysql":      ("cylinder",        Color(hex: 0x00758F)),
        "mariadb":    ("cylinder",        Color(hex: 0x00758F)),
        "sqlite3":    ("cylinder",        Color(hex: 0x003B57)),
        "redis-cli":  ("cylinder",        Color(hex: 0xDC382D)),
        "mongosh":    ("cylinder",        Color(hex: 0x47A248)),
        "mongo":      ("cylinder",        Color(hex: 0x47A248)),
        // Monitoring
        "top":        ("chart.bar",       Color(hex: 0x00AEFF)),
        "htop":       ("chart.bar",       Color(hex: 0x00AEFF)),
        "btop":       ("chart.bar",       Color(hex: 0x00AEFF)),
        "mactop":     ("chart.bar",       Color(hex: 0x00AEFF)),
        // Multiplexers
        "tmux":       ("rectangle.split.3x1", Color(hex: 0x1BB91F)),
        "screen":     ("rectangle.split.3x1", Color(hex: 0xAAAAAA)),
        // Search
        "grep":       ("magnifyingglass", Color(hex: 0x9CCC65)),
        "rg":         ("magnifyingglass", Color(hex: 0x9CCC65)),
        "find":       ("magnifyingglass", Color(hex: 0x9CCC65)),
        "fd":         ("magnifyingglass", Color(hex: 0x9CCC65)),
        "ag":         ("magnifyingglass", Color(hex: 0x9CCC65)),
        "fzf":        ("magnifyingglass", Color(hex: 0x9CCC65)),
        // Data processing
        "jq":         ("text.line.first.and.arrowtriangle.forward", Color(hex: 0xCCCCCC)),
        "yq":         ("text.line.first.and.arrowtriangle.forward", Color(hex: 0xCCCCCC)),
        "sed":        ("text.line.first.and.arrowtriangle.forward", Color(hex: 0xAAAAAA)),
        "awk":        ("text.line.first.and.arrowtriangle.forward", Color(hex: 0xAAAAAA)),
        // Files
        "less":       ("doc.text",        Color(hex: 0xAAAAAA)),
        "more":       ("doc.text",        Color(hex: 0xAAAAAA)),
        "cat":        ("doc.text",        Color(hex: 0xAAAAAA)),
        "bat":        ("doc.text",        Color(hex: 0xAAAAAA)),
        "tail":       ("doc.text",        Color(hex: 0xAAAAAA)),
        "tree":       ("folder",          Color(hex: 0xAAAAAA)),
        // Archive
        "tar":        ("doc.zipper",      Color(hex: 0xFD9126)),
        "zip":        ("doc.zipper",      Color(hex: 0xFD9126)),
        "unzip":      ("doc.zipper",      Color(hex: 0xFD9126)),
        "gzip":       ("doc.zipper",      Color(hex: 0xFD9126)),
        // Media
        "ffmpeg":     ("film",            Color(hex: 0x007808)),
        "ffprobe":    ("film",            Color(hex: 0x007808)),
        // Testing
        "pytest":     ("checkmark.circle", Color(hex: 0xFFDF59)),
        "jest":       ("checkmark.circle", Color(hex: 0xC63D14)),
        "mocha":      ("checkmark.circle", Color(hex: 0x8D6748)),
        "rspec":      ("checkmark.circle", Color(hex: 0xCC342D)),
        // Debugging
        "lldb":       ("ant",             Color(hex: 0x147EFB)),
        "gdb":        ("ant",             Color(hex: 0x00AEFF)),
        "dtrace":     ("ant",             Color(hex: 0xAAAAAA)),
        "dtruss":     ("ant",             Color(hex: 0xAAAAAA)),
        // System
        "sudo":       ("lock.shield",     Color(hex: 0xFF6B6B)),
        "ps":         ("chart.bar",       Color(hex: 0xAAAAAA)),
        "kill":       ("xmark.circle",    Color(hex: 0xFF6B6B)),
        "killall":    ("xmark.circle",    Color(hex: 0xFF6B6B)),
        "df":         ("internaldrive",   Color(hex: 0xAAAAAA)),
        "du":         ("internaldrive",   Color(hex: 0xAAAAAA)),
        "chmod":      ("lock",            Color(hex: 0xAAAAAA)),
        "chown":      ("lock",            Color(hex: 0xAAAAAA)),
        // AI
        "claude":     ("brain",           Color(hex: 0xDA7756)),
        "codex":      ("brain",           Color(hex: 0x10A37F)),
        "gemini":     ("brain",           Color(hex: 0x4285F4)),
        // Misc
        "sleep":      ("moon.zzz",        Color(hex: 0x8888AA)),
        "watch":      ("clock.arrow.2.circlepath", Color(hex: 0x00AEFF)),
        "man":        ("book",            Color(hex: 0xAAAAAA)),
        "time":       ("clock",           Color(hex: 0xAAAAAA)),
        "env":        ("gearshape",       Color(hex: 0xAAAAAA)),
        "xargs":      ("gearshape",       Color(hex: 0xAAAAAA)),
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
        .background(Theme.backgroundHover.opacity(isHovered ? 1 : 0))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: Theme.borderWidth)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

private struct TabButton: View {
    let tabId: UUID
    let title: String
    let isActive: Bool
    let isRunning: Bool
    let isTmuxPane: Bool
    let executablePath: String?
    let tabColor: TabColor?
    let paneCount: Int
    let tabCount: Int
    let isLastTab: Bool
    let showDivider: Bool
    let index: Int
    let showIndex: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onSetColor: (TabColor?) -> Void
    let onCloseOthers: () -> Void
    let onCloseToRight: () -> Void
    let onCloseAll: () -> Void

    @State private var isHovered = false
    @State private var closeHovered = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var lastTapTime: Date = .distantPast
    @FocusState private var editFocused: Bool

    private var canClose: Bool { tabCount > 1 }

    var body: some View {
        ZStack {
            if isActive {
                Color(nsColor: TerminalTheme.background)
            } else {
                Theme.backgroundHover.opacity(isHovered ? 1 : 0)
            }

            if let tabColor {
                isActive ? tabColor.tint : tabColor.tint.opacity(0.6)
            }

            HStack(spacing: 6) {
                // Close button visible on hover; icon always present.
                // ZStack keeps the icon fixed while close button appears alongside.
                ZStack {
                    ProcessIcon(
                        path: isTmuxPane ? "tmux" : executablePath,
                        colorOverride: !isActive ? inactiveColor : nil
                    )
                    .opacity(showIndex && index <= 9 ? 0 : (canClose && isHovered && !showIndex ? 0 : 1))

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
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.backgroundPanel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .onSubmit { commitEdit() }
                        .onExitCommand { cancelEdit() }
                        .onKeyPress(.escape) { cancelEdit(); return .handled }
                        .onChange(of: editFocused) { _, focused in
                            if !focused { commitEdit() }
                        }
                } else {
                    Text(title)
                        .font(Theme.labelFont)
                        .foregroundStyle(isActive ? Theme.textPrimary : inactiveColor)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if paneCount > 1 {
                        Text("\(paneCount)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.backgroundPanel)
                            )
                    }
                }

                Spacer()

                if isRunning && !isActive {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(inactiveColor)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .overlay {
            if isActive {
                HStack {
                    Rectangle().fill(Theme.border).frame(width: Theme.borderWidth)
                    Spacer()
                    Rectangle().fill(Theme.border).frame(width: Theme.borderWidth)
                }
                .padding(.bottom, -2)
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
        .terminalTabContextMenu(
            tabId: tabId,
            tabCount: tabCount,
            isLastTab: isLastTab,
            tabColor: tabColor,
            onRename: { startEditing() },
            onSetColor: onSetColor,
            onClose: onClose,
            onCloseOthers: onCloseOthers,
            onCloseToRight: onCloseToRight,
            onCloseAll: onCloseAll
        )
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
        .overlay { MiddleClickHandler { if canClose { onClose() } } }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }

    private var inactiveColor: Color {
        if let tabColor, tabColor != .base { return tabColor.color.opacity(0.35) }
        return Theme.textSecondary
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
