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
    private var tabManager: TerminalTabManager?
    private var splitViewController: MainSplitViewController?
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
        let screenFrame = resolveScreen().visibleFrame
        let targetFrame = Self.calculateFrame(
            position: position, screenFrame: screenFrame, sizePercent: sizePercent
        )

        switch animation {
        case .slide:
            let startFrame = Self.offscreenFrame(
                position: position, targetFrame: targetFrame, screenFrame: screenFrame
            )
            win.setFrame(startFrame, display: false)
            win.alphaValue = 1
            win.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                win.animator().setFrame(targetFrame, display: true)
            }

        case .fade:
            win.setFrame(targetFrame, display: false)
            win.alphaValue = 0
            win.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                win.animator().alphaValue = 1
            }

        case .instant:
            win.setFrame(targetFrame, display: true)
            win.alphaValue = 1
            win.orderFront(nil)
        }

        win.makeKey()
        isVisible = true
        installFocusLossObserver()
    }

    // MARK: - Hide

    func hide() {
        guard let win = window, isVisible else { return }
        removeFocusLossObserver()

        let screenFrame = resolveScreen().visibleFrame

        switch animation {
        case .slide:
            let targetFrame = win.frame
            let offscreen = Self.offscreenFrame(
                position: position, targetFrame: targetFrame, screenFrame: screenFrame
            )
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                win.animator().setFrame(offscreen, display: true)
            } completionHandler: {
                win.orderOut(nil)
            }

        case .fade:
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                win.animator().alphaValue = 0
            } completionHandler: {
                win.orderOut(nil)
            }

        case .instant:
            win.orderOut(nil)
        }

        isVisible = false
    }

    // MARK: - Reposition

    func repositionWindow() {
        guard let win = window, isVisible else { return }
        let screenFrame = resolveScreen().visibleFrame
        let frame = Self.calculateFrame(
            position: position, screenFrame: screenFrame, sizePercent: sizePercent
        )
        win.setFrame(frame, display: true)
    }

    // MARK: - Collection Behavior

    func updateCollectionBehavior() {
        guard let win = window else { return }
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle]
        if allSpaces { behavior.insert(.canJoinAllSpaces) }
        win.collectionBehavior = behavior
        win.level = floating ? .floating : .normal
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
        isVisible = false
    }

    // MARK: - Window Creation

    private func ensureWindow() -> NSWindow {
        if let existing = window { return existing }

        let tm = TerminalTabManager()
        let splitVC = MainSplitViewController(tabManager: tm)

        // Collapse sidebar unless setting says to show it
        if !showSidebar, splitVC.splitViewItems.count > 1 {
            splitVC.splitViewItems[1].isCollapsed = true
        }

        let win = HotkeyPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        win.backgroundColor = TerminalTheme.background
        let schemeName = UserDefaults.standard.string(forKey: "terminalColorScheme") ?? "hexed"
        let bg = TerminalColorScheme.named(schemeName).background
        let brightness = (Int(bg.r) * 299 + Int(bg.g) * 587 + Int(bg.b) * 114) / 1000
        win.appearance = NSAppearance(named: brightness > 128 ? .aqua : .darkAqua)

        win.contentViewController = splitVC
        win.hasShadow = true
        win.isOpaque = false

        updateCollectionBehaviorFor(win)

        self.window = win
        self.tabManager = tm
        self.splitViewController = splitVC

        return win
    }

    private func updateCollectionBehaviorFor(_ win: NSWindow) {
        var behavior: NSWindow.CollectionBehavior = [.ignoresCycle]
        if allSpaces { behavior.insert(.canJoinAllSpaces) }
        win.collectionBehavior = behavior
        win.level = floating ? .floating : .normal
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
