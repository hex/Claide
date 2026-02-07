// ABOUTME: Application delegate that owns terminal windows and the terminal menu.
// ABOUTME: Creates new windows with Cmd+N, each with its own tab manager.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowControllers: [MainWindowController] = []

    private var keyMonitor: Any?

    /// The tab manager for the currently active (key) window.
    private var activeTabManager: TerminalTabManager? {
        activeWindowController?.tabManager
    }

    /// The window controller for the currently active (key) window.
    private var activeWindowController: MainWindowController? {
        guard let keyWindow = NSApp.keyWindow else {
            return windowControllers.first
        }
        return windowControllers.first { $0.window === keyWindow }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        createNewWindow()

        // SwiftUI builds the main menu asynchronously after launch.
        // Delay so our Terminal menu is appended after SwiftUI's menu is in place.
        DispatchQueue.main.async { self.installTerminalMenu() }

        installKeyMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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

    @objc private func toggleSidebar() {
        activeWindowController?.splitViewController.toggleSidebarPanel()
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
