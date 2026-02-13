// ABOUTME: Application delegate that owns terminal windows and the terminal menu.
// ABOUTME: Creates new windows with Cmd+N, each with its own tab manager.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [MainWindowController] = []

    private var keyMonitor: Any?

    // MARK: - Hotkey Window

    private var hotkeyWindowController: HotkeyWindowController?
    private var globalHotkey: GlobalHotkey?
    private var settingsObserver: Any?

    /// The terminal view for the currently focused pane.
    private var activeTerminalView: GhosttyTerminalView? {
        activeTabManager?.activeTab?.terminalView
    }

    /// The tab manager for the currently active (key) window.
    private var activeTabManager: TerminalTabManager? {
        if let keyWindow = NSApp.keyWindow,
           keyWindow === hotkeyWindowController?.window {
            return hotkeyWindowController?.tabManager
        }
        return activeWindowController?.tabManager
    }

    /// The window controller for the currently active (key) window.
    private var activeWindowController: MainWindowController? {
        guard let keyWindow = NSApp.keyWindow else {
            return windowControllers.first
        }
        return windowControllers.first { $0.window === keyWindow }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        GhosttyApp.shared.start()

        if !restoreSession() {
            createNewWindow()
        }

        // SwiftUI builds the main menu asynchronously after launch.
        // Delay so our Terminal menu is appended after SwiftUI's menu is in place.
        DispatchQueue.main.async { self.installTerminalMenu() }

        installKeyMonitor()
        setupHotkeyWindow()
        observeHotkeySettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveSession()
        hotkeyWindowController?.teardown()
        globalHotkey = nil
        GhosttyApp.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app alive when hotkey window is enabled — it runs without visible windows
        !UserDefaults.standard.bool(forKey: "hotkeyEnabled")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            createNewWindow()
        }
        return true
    }

    // MARK: - Window Management

    @discardableResult
    private func createNewWindow() -> MainWindowController {
        let tabManager = TerminalTabManager()
        let controller = MainWindowController(tabManager: tabManager)
        windowControllers.append(controller)

        // Cascade new windows from the most recent existing window
        if let existingWindow = windowControllers.dropLast().last?.window,
           let newWindow = controller.window {
            let cascaded = newWindow.cascadeTopLeft(from: existingWindow.frame.origin)
            newWindow.setFrameTopLeftPoint(cascaded)
        }

        controller.showWindow(nil)

        // Track window close to remove from our array.
        // MainWindowController is its own NSWindowDelegate (for fullscreen),
        // so we observe the notification instead of setting the delegate.
        if let window = controller.window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
        }

        return controller
    }

    // MARK: - Session Persistence

    private func saveSession() {
        let windowStates = windowControllers.compactMap { controller -> WindowState? in
            guard let window = controller.window else { return nil }
            let tabStates = controller.tabManager.captureTabStates()
            let activeIndex = controller.tabManager.tabs.firstIndex(where: {
                $0.id == controller.tabManager.activeTabID
            }) ?? 0
            return WindowState(
                frame: CodableRect(window.frame),
                tabs: tabStates,
                activeTabIndex: activeIndex
            )
        }
        SessionPersistence.save(SessionState(windows: windowStates))
    }

    /// Restore windows from saved session state.
    /// Returns true if at least one window was restored.
    @discardableResult
    private func restoreSession() -> Bool {
        guard let state = SessionPersistence.load(), !state.windows.isEmpty else {
            return false
        }

        for windowState in state.windows {
            let tabManager = TerminalTabManager()
            for tabState in windowState.tabs {
                tabManager.restoreTab(state: tabState)
            }
            if windowState.activeTabIndex < tabManager.tabs.count {
                tabManager.activeTabID = tabManager.tabs[windowState.activeTabIndex].id
            }

            let controller = MainWindowController(tabManager: tabManager)
            windowControllers.append(controller)
            controller.window?.setFrame(windowState.frame.cgRect, display: false)
            controller.showWindow(nil)

            if let window = controller.window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidClose(_:)),
                    name: NSWindow.willCloseNotification,
                    object: window
                )
            }
        }

        return true
    }

    // MARK: - Hotkey Window Setup

    private func setupHotkeyWindow() {
        guard UserDefaults.standard.bool(forKey: "hotkeyEnabled") else { return }
        registerGlobalHotkey()
    }

    private func registerGlobalHotkey() {
        globalHotkey = nil

        let keyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        guard keyCode >= 0 else { return }

        let modifierRaw = UInt(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierRaw)

        globalHotkey = GlobalHotkey(
            keyCode: UInt32(keyCode),
            modifiers: modifiers
        ) { [weak self] in
            self?.toggleHotkeyWindow()
        }
    }

    private func toggleHotkeyWindow() {
        if hotkeyWindowController == nil {
            hotkeyWindowController = HotkeyWindowController()
        }
        hotkeyWindowController?.toggle()
    }

    private func observeHotkeySettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.handleHotkeySettingsChange()
        }
    }

    private func handleHotkeySettingsChange() {
        let enabled = UserDefaults.standard.bool(forKey: "hotkeyEnabled")

        if enabled {
            registerGlobalHotkey()
            hotkeyWindowController?.updateCollectionBehavior()
            hotkeyWindowController?.updateSidebarVisibility()
        } else {
            globalHotkey = nil
            hotkeyWindowController?.teardown()
            hotkeyWindowController = nil
        }
    }

    // MARK: - Terminal Menu

    private var terminalMenuInstalled = false

    private func installTerminalMenu() {
        guard !terminalMenuInstalled, let mainMenu = NSApp.mainMenu else { return }
        terminalMenuInstalled = true

        let menu = NSMenu(title: "Terminal")

        let newWindow = NSMenuItem(title: "New Window", action: #selector(newWindow), keyEquivalent: "n")
        newWindow.target = self
        menu.addItem(newWindow)

        let newTab = NSMenuItem(title: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        newTab.target = self
        menu.addItem(newTab)

        let closePane = NSMenuItem(title: "Close Pane", action: #selector(closeActivePane), keyEquivalent: "w")
        closePane.target = self
        menu.addItem(closePane)

        menu.addItem(.separator())

        let splitH = NSMenuItem(title: "Split Horizontally", action: #selector(splitHorizontal), keyEquivalent: "d")
        splitH.target = self
        menu.addItem(splitH)

        let splitV = NSMenuItem(title: "Split Vertically", action: #selector(splitVertical), keyEquivalent: "D")
        splitV.keyEquivalentModifierMask = [.command, .shift]
        splitV.target = self
        menu.addItem(splitV)

        menu.addItem(.separator())

        let sidebar = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "b")
        sidebar.target = self
        menu.addItem(sidebar)

        let palette = NSMenuItem(title: "Command Palette", action: #selector(showCommandPalette), keyEquivalent: "p")
        palette.target = self
        menu.addItem(palette)

        menu.addItem(.separator())

        let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(fontZoomIn), keyEquivalent: "+")
        zoomIn.target = self
        menu.addItem(zoomIn)

        let zoomOut = NSMenuItem(title: "Zoom Out", action: #selector(fontZoomOut), keyEquivalent: "-")
        zoomOut.target = self
        menu.addItem(zoomOut)

        let zoomReset = NSMenuItem(title: "Reset Zoom", action: #selector(fontZoomReset), keyEquivalent: "0")
        zoomReset.target = self
        menu.addItem(zoomReset)

        menu.addItem(.separator())

        for i in 1...9 {
            let item = NSMenuItem(
                title: "Tab \(i)",
                action: #selector(switchToTab(_:)),
                keyEquivalent: "\(i)"
            )
            item.target = self
            item.tag = i - 1
            menu.addItem(item)
        }

        let menuBarItem = NSMenuItem()
        menuBarItem.submenu = menu
        mainMenu.addItem(menuBarItem)
    }

    // MARK: - Key Monitor

    /// Global key monitor for terminal shortcuts. Fires at the NSApplication level
    /// before any view's performKeyEquivalent, bypassing SwiftUI's responder chain
    /// which can silently swallow key events.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags == .command, let chars = event.charactersIgnoringModifiers {
                switch chars {
                case "n":
                    self.newWindow()
                    return nil
                case "t":
                    self.newTab()
                    return nil
                case "w":
                    self.closeActivePane()
                    return nil
                case "d":
                    self.splitHorizontal()
                    return nil
                case "b":
                    self.toggleSidebar()
                    return nil
                case "p":
                    self.toggleCommandPalette()
                    return nil
                case "+", "=":
                    self.activeTerminalView?.increaseFontSize()
                    return nil
                case "-":
                    self.activeTerminalView?.decreaseFontSize()
                    return nil
                case "0":
                    self.activeTerminalView?.resetFontSize()
                    return nil
                default:
                    break
                }
            }

            if flags == [.command, .option] {
                switch event.keyCode {
                case 123: // Left arrow
                    self.activeTabManager?.focusAdjacentPane(direction: .left)
                    return nil
                case 124: // Right arrow
                    self.activeTabManager?.focusAdjacentPane(direction: .right)
                    return nil
                case 126: // Up arrow
                    self.activeTabManager?.focusAdjacentPane(direction: .up)
                    return nil
                case 125: // Down arrow
                    self.activeTabManager?.focusAdjacentPane(direction: .down)
                    return nil
                default:
                    break
                }
            }

            if flags == [.command, .shift] {
                // Cmd+Shift+Enter: toggle pane zoom
                if event.keyCode == 36 {
                    self.activeTabManager?.toggleZoom()
                    return nil
                }
            }

            if flags == [.command, .shift], let chars = event.charactersIgnoringModifiers {
                switch chars {
                case "D":
                    self.splitVertical()
                    return nil
                default:
                    break
                }

                switch event.keyCode {
                case 123: // Left arrow
                    self.moveActiveTabLeft()
                    return nil
                case 124: // Right arrow
                    self.moveActiveTabRight()
                    return nil
                default:
                    break
                }
            }

            return event
        }
    }

    // MARK: - Actions

    @objc private func newWindow() {
        createNewWindow()
    }

    @objc private func newTab() {
        activeTabManager?.addTab()
    }

    @objc private func closeActivePane() {
        guard let tabManager = activeTabManager else { return }
        // If there's only one tab with one pane, close the window instead
        if tabManager.tabs.count == 1,
           tabManager.activeTab?.paneController.paneTree.paneCount == 1 {
            activeWindowController?.window?.close()
            return
        }
        tabManager.closeActivePane()
    }

    @objc private func splitHorizontal() {
        activeTabManager?.splitActivePane(axis: .horizontal)
    }

    @objc private func splitVertical() {
        activeTabManager?.splitActivePane(axis: .vertical)
    }

    @objc private func fontZoomIn() {
        activeTerminalView?.increaseFontSize()
    }

    @objc private func fontZoomOut() {
        activeTerminalView?.decreaseFontSize()
    }

    @objc private func fontZoomReset() {
        activeTerminalView?.resetFontSize()
    }

    @objc private func showCommandPalette() {
        toggleCommandPalette()
    }

    private func toggleCommandPalette() {
        if let keyWindow = NSApp.keyWindow,
           keyWindow === hotkeyWindowController?.window {
            hotkeyWindowController?.splitViewController?.paletteManager.toggle()
        } else {
            activeWindowController?.toggleCommandPalette()
        }
    }

    @objc private func toggleSidebar() {
        if let keyWindow = NSApp.keyWindow,
           keyWindow === hotkeyWindowController?.window {
            hotkeyWindowController?.splitViewController?.toggleSidebarPanel()
        } else {
            activeWindowController?.splitViewController.toggleSidebarPanel()
        }
    }

    @objc private func switchToTab(_ sender: NSMenuItem) {
        activeTabManager?.switchToTab(at: sender.tag)
    }

    private func moveActiveTabLeft() {
        guard let tabManager = activeTabManager,
              let id = tabManager.activeTabID,
              let index = tabManager.tabs.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        tabManager.moveTab(from: index, to: index - 1)
    }

    private func moveActiveTabRight() {
        guard let tabManager = activeTabManager,
              let id = tabManager.activeTabID,
              let index = tabManager.tabs.firstIndex(where: { $0.id == id }),
              index < tabManager.tabs.count - 1 else { return }
        tabManager.moveTab(from: index, to: index + 1)
    }

    @objc private func windowDidClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        windowControllers.removeAll { $0.window === closingWindow }
    }
}

// MARK: - Menu Validation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(closeActivePane):
            return activeTabManager != nil
        case #selector(switchToTab(_:)):
            guard let tabManager = activeTabManager else { return false }
            return menuItem.tag < tabManager.tabs.count
        default:
            return true
        }
    }
}
