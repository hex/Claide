// ABOUTME: Manages a borderless floating window that slides in from a screen edge.
// ABOUTME: Toggled by a global hotkey, independent of regular window lifecycle.

import AppKit

/// Screen edge from which the hotkey window appears.
enum HotkeyPosition: String, CaseIterable {
    case top, bottom, left, right
}

/// Animation style for show/hide transitions.
enum HotkeyAnimation: String, CaseIterable {
    case slide, fade, instant
}

/// Which screen to display the hotkey window on.
enum HotkeyScreen: String, CaseIterable {
    case cursor, primary
}

@MainActor
final class HotkeyWindowController {

    private(set) var window: NSWindow?
    private(set) var tabManager: TerminalTabManager?
    private(set) var splitViewController: MainSplitViewController?
    private var notchInsetConstraint: NSLayoutConstraint?
    private var edgeBorderView: NSView?
    private var isVisible = false
    private var focusLossObserver: Any?

    // MARK: - Configuration (read from UserDefaults on each toggle)

    var position: HotkeyPosition {
        HotkeyPosition(rawValue: UserDefaults.standard.string(forKey: "hotkeyPosition") ?? "top") ?? .top
    }

    var sizePercent: Double {
        UserDefaults.standard.double(forKey: "hotkeySize").clamped(to: 10...100, default: 50)
    }

    var animation: HotkeyAnimation {
        HotkeyAnimation(rawValue: UserDefaults.standard.string(forKey: "hotkeyAnimation") ?? "slide") ?? .slide
    }

    var animationDuration: Double {
        UserDefaults.standard.double(forKey: "hotkeyAnimationDuration").clamped(to: 0.05...0.5, default: 0.2)
    }

    var hideOnFocusLoss: Bool {
        UserDefaults.standard.bool(forKey: "hotkeyHideOnFocusLoss")
    }

    var allSpaces: Bool {
        UserDefaults.standard.bool(forKey: "hotkeyAllSpaces")
    }

    var showSidebar: Bool {
        UserDefaults.standard.bool(forKey: "hotkeyShowSidebar")
    }

    var floating: Bool {
        UserDefaults.standard.bool(forKey: "hotkeyFloating")
    }

    var screen: HotkeyScreen {
        HotkeyScreen(rawValue: UserDefaults.standard.string(forKey: "hotkeyScreen") ?? "cursor") ?? .cursor
    }

    // MARK: - Toggle

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Show

    func show() {
        let win = ensureWindow()
        let currentScreen = resolveScreen()
        let screenFrame = currentScreen.frame
        let targetFrame = Self.calculateFrame(
            position: position, screenFrame: screenFrame, sizePercent: sizePercent
        )

        updateNotchInset(for: currentScreen)
        updateEdgeBorder()

        // .nonactivatingPanel lets us order the window without triggering an app
        // activation space switch. We remove it after activation (see below).
        win.styleMask.insert(.nonactivatingPanel)

        // Use .moveToActiveSpace so the window lands on the current space (including
        // fullscreen spaces). .canJoinAllSpaces overrides it, so we set that after.
        win.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]

        switch animation {
        case .slide:
            let startFrame = Self.offscreenFrame(
                position: position, targetFrame: targetFrame, screenFrame: screenFrame
            )
            win.setFrame(startFrame, display: false)
            win.alphaValue = 1
            win.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                win.setFrame(targetFrame, display: true)
            }

        case .fade:
            win.setFrame(targetFrame, display: false)
            win.alphaValue = 0
            win.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                win.animator().alphaValue = 1
            }

        case .instant:
            win.setFrame(targetFrame, display: true)
            win.alphaValue = 1
            win.orderFrontRegardless()
        }

        // Activate on the next run loop — by then the window is already on the
        // current space, so macOS activates in-place instead of switching spaces.
        // Remove .nonactivatingPanel so menu key equivalents route normally.
        DispatchQueue.main.async { [weak self] in
            win.styleMask.remove(.nonactivatingPanel)
            NSApp.activate()
            win.makeKey()
            self?.updateCollectionBehavior()
        }

        isVisible = true
        installFocusLossObserver()
    }

    // MARK: - Hide

    func hide() {
        guard let win = window, isVisible else { return }
        removeFocusLossObserver()
        isVisible = false

        let screenFrame = resolveScreen().frame

        switch animation {
        case .slide:
            let targetFrame = win.frame
            let offscreen = Self.offscreenFrame(
                position: position, targetFrame: targetFrame, screenFrame: screenFrame
            )
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                ctx.allowsImplicitAnimation = true
                win.setFrame(offscreen, display: true)
            } completionHandler: { [weak self] in
                win.orderOut(nil)
                self?.yieldFocusIfNeeded()
            }

        case .fade:
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                win.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                win.orderOut(nil)
                self?.yieldFocusIfNeeded()
            }

        case .instant:
            win.orderOut(nil)
            yieldFocusIfNeeded()
        }
    }

    /// If no other Claide windows are visible, hide the app so the previous app regains focus.
    private func yieldFocusIfNeeded() {
        let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && $0 !== window }
        if !hasVisibleWindows {
            NSApp.hide(nil)
        }
    }

    // MARK: - Sidebar

    func updateSidebarVisibility() {
        guard let splitVC = splitViewController, splitVC.splitViewItems.count > 1 else { return }
        let sidebarItem = splitVC.splitViewItems[1]
        if sidebarItem.isCollapsed == showSidebar {
            sidebarItem.isCollapsed = !showSidebar
        }
    }

    // MARK: - Reposition

    func repositionWindow() {
        guard let win = window, isVisible else { return }
        let currentScreen = resolveScreen()
        let screenFrame = currentScreen.frame
        let frame = Self.calculateFrame(
            position: position, screenFrame: screenFrame, sizePercent: sizePercent
        )
        win.setFrame(frame, display: true)
        updateNotchInset(for: currentScreen)
        updateEdgeBorder()
    }

    // MARK: - Edge Border

    /// Position a 1px border on the exposed edge (the edge facing the screen interior).
    /// Hidden when the window covers the full screen dimension.
    private func updateEdgeBorder() {
        guard let border = edgeBorderView, let container = border.superview else { return }

        // Remove old constraints on the border before adding new ones.
        NSLayoutConstraint.deactivate(border.constraints)
        for constraint in container.constraints where constraint.firstItem === border || constraint.secondItem === border {
            constraint.isActive = false
        }

        let thickness: CGFloat = 1
        let fullSize = sizePercent >= 100
        border.isHidden = fullSize

        switch position {
        case .top:
            NSLayoutConstraint.activate([
                border.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                border.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                border.heightAnchor.constraint(equalToConstant: thickness),
            ])
        case .bottom:
            NSLayoutConstraint.activate([
                border.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                border.topAnchor.constraint(equalTo: container.topAnchor),
                border.heightAnchor.constraint(equalToConstant: thickness),
            ])
        case .left:
            NSLayoutConstraint.activate([
                border.topAnchor.constraint(equalTo: container.topAnchor),
                border.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                border.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                border.widthAnchor.constraint(equalToConstant: thickness),
            ])
        case .right:
            NSLayoutConstraint.activate([
                border.topAnchor.constraint(equalTo: container.topAnchor),
                border.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                border.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                border.widthAnchor.constraint(equalToConstant: thickness),
            ])
        }
    }

    // MARK: - Notch Inset

    /// Inset content below the notch on screens that have one.
    /// Uses auxiliaryTopLeftArea to detect notch screens — safeAreaInsets.top includes
    /// the menu bar on all screens, but we only need to inset for the physical notch.
    private func updateNotchInset(for screen: NSScreen) {
        guard position != .bottom else {
            notchInsetConstraint?.constant = 0
            return
        }
        let hasNotch = screen.auxiliaryTopLeftArea != nil
        notchInsetConstraint?.constant = hasNotch ? screen.safeAreaInsets.top : 0
    }

    // MARK: - Collection Behavior

    func updateCollectionBehavior() {
        guard let win = window else { return }
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        if allSpaces { behavior.insert(.canJoinAllSpaces) }
        win.collectionBehavior = behavior
        win.level = floating ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2) : .normal
    }

    // MARK: - Teardown

    func teardown() {
        removeFocusLossObserver()
        if let win = window {
            win.orderOut(nil)
        }
        window = nil
        tabManager = nil
        splitViewController = nil
        notchInsetConstraint = nil
        edgeBorderView = nil
        isVisible = false
    }

    // MARK: - Window Creation

    private func ensureWindow() -> NSWindow {
        if let existing = window { return existing }

        let tm = TerminalTabManager()
        let splitVC = MainSplitViewController(tabManager: tm, isHotkeyWindow: true)

        // Collapse sidebar unless setting says to show it.
        // Must run after viewDidAppear (which calls restoreSidebarState from UserDefaults).
        if !showSidebar {
            DispatchQueue.main.async {
                if splitVC.splitViewItems.count > 1 {
                    splitVC.splitViewItems[1].isCollapsed = true
                }
            }
        }

        let win = HotkeyPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.hidesOnDeactivate = false

        win.backgroundColor = .black
        win.appearance = NSAppearance(named: .darkAqua)

        // Use a container content view so we can inset the terminal below the notch.
        // The notch area shows the window background color; content starts below it.
        let container = NSView()
        container.wantsLayer = true
        splitVC.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(splitVC.view)

        let topConstraint = splitVC.view.topAnchor.constraint(equalTo: container.topAnchor)
        NSLayoutConstraint.activate([
            topConstraint,
            splitVC.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitVC.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            splitVC.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // 1px border on the exposed edge (opposite the screen edge the window is anchored to).
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(border)
        self.edgeBorderView = border

        win.contentView = container
        win.hasShadow = false
        win.isOpaque = false

        updateCollectionBehaviorFor(win)

        self.window = win
        self.tabManager = tm
        self.splitViewController = splitVC
        self.notchInsetConstraint = topConstraint

        return win
    }

    private func updateCollectionBehaviorFor(_ win: NSWindow) {
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        if allSpaces { behavior.insert(.canJoinAllSpaces) }
        win.collectionBehavior = behavior
        // .floating (3) is below the menu bar (.mainMenu = 24).
        // Use a level above the menu bar so the hotkey window covers it.
        win.level = floating ? NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2) : .normal
    }

    // MARK: - Focus Loss

    private func installFocusLossObserver() {
        guard hideOnFocusLoss else { return }
        removeFocusLossObserver()

        focusLossObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // Delay to avoid hiding during transient focus changes (context menus, etc.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let self, self.isVisible else { return }
                guard let win = self.window, !win.isKeyWindow else { return }
                // Don't hide if the new key window belongs to our app (e.g., Settings)
                if let keyWindow = NSApp.keyWindow, keyWindow !== win {
                    self.hide()
                }
            }
        }
    }

    private func removeFocusLossObserver() {
        if let observer = focusLossObserver {
            NotificationCenter.default.removeObserver(observer)
            focusLossObserver = nil
        }
    }

    // MARK: - Screen Resolution

    private func resolveScreen() -> NSScreen {
        switch screen {
        case .cursor:
            let mouseLocation = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
                ?? NSScreen.main ?? NSScreen.screens[0]
        case .primary:
            return NSScreen.main ?? NSScreen.screens[0]
        }
    }

    // MARK: - Frame Calculations (static, testable)

    /// Calculate the target window frame for a given position on a screen.
    static func calculateFrame(
        position: HotkeyPosition,
        screenFrame: NSRect,
        sizePercent: Double
    ) -> NSRect {
        let pct = sizePercent / 100.0
        switch position {
        case .top:
            let h = screenFrame.height * pct
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.maxY - h,
                width: screenFrame.width,
                height: h
            )
        case .bottom:
            let h = screenFrame.height * pct
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: screenFrame.width,
                height: h
            )
        case .left:
            let w = screenFrame.width * pct
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: w,
                height: screenFrame.height
            )
        case .right:
            let w = screenFrame.width * pct
            return NSRect(
                x: screenFrame.origin.x + screenFrame.width - w,
                y: screenFrame.origin.y,
                width: w,
                height: screenFrame.height
            )
        }
    }

    /// Calculate the offscreen starting frame for slide animation.
    static func offscreenFrame(
        position: HotkeyPosition,
        targetFrame: NSRect,
        screenFrame: NSRect
    ) -> NSRect {
        var frame = targetFrame
        switch position {
        case .top:
            frame.origin.y = screenFrame.maxY
        case .bottom:
            frame.origin.y = screenFrame.origin.y - targetFrame.height
        case .left:
            frame.origin.x = screenFrame.origin.x - targetFrame.width
        case .right:
            frame.origin.x = screenFrame.maxX
        }
        return frame
    }
}

// MARK: - HotkeyPanel

/// Borderless NSWindow subclass that can become key (borderless windows can't by default).
private final class HotkeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Double Clamping

private extension Double {
    func clamped(to range: ClosedRange<Double>, default fallback: Double) -> Double {
        if self == 0 { return fallback }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
