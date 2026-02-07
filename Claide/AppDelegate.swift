// ABOUTME: Application delegate that owns the main window and terminal menu.
// ABOUTME: Creates TerminalTabManager and MainWindowController at launch.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var tabManager: TerminalTabManager!
    private var windowController: MainWindowController!

    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        tabManager = TerminalTabManager()
        windowController = MainWindowController(tabManager: tabManager)
        windowController.showWindow(nil)

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
            windowController?.showWindow(self)
        }
        return true
    }

    // MARK: - Terminal Menu

    private var terminalMenuInstalled = false

    private func installTerminalMenu() {
        guard !terminalMenuInstalled, let mainMenu = NSApp.mainMenu else { return }
        terminalMenuInstalled = true

        let menu = NSMenu(title: "Terminal")

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
                    self.tabManager.focusAdjacentPane(direction: .left)
                    return nil
                case 124: // Right arrow
                    self.tabManager.focusAdjacentPane(direction: .right)
                    return nil
                case 126: // Up arrow
                    self.tabManager.focusAdjacentPane(direction: .up)
                    return nil
                case 125: // Down arrow
                    self.tabManager.focusAdjacentPane(direction: .down)
                    return nil
                default:
                    break
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

    @objc private func newTab() {
        tabManager.addTab()
    }

    @objc private func closeActivePane() {
        tabManager.closeActivePane()
    }

    @objc private func splitHorizontal() {
        tabManager.splitActivePane(axis: .horizontal)
    }

    @objc private func splitVertical() {
        tabManager.splitActivePane(axis: .vertical)
    }

    @objc private func toggleSidebar() {
        windowController.splitViewController.toggleSidebarPanel()
    }

    @objc private func switchToTab(_ sender: NSMenuItem) {
        tabManager.switchToTab(at: sender.tag)
    }

    private func moveActiveTabLeft() {
        guard let id = tabManager.activeTabID,
              let index = tabManager.tabs.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        tabManager.moveTab(from: index, to: index - 1)
    }

    private func moveActiveTabRight() {
        guard let id = tabManager.activeTabID,
              let index = tabManager.tabs.firstIndex(where: { $0.id == id }),
              index < tabManager.tabs.count - 1 else { return }
        tabManager.moveTab(from: index, to: index + 1)
    }
}

// MARK: - Menu Validation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(closeActivePane):
            let hasManyTabs = tabManager.tabs.count > 1
            let hasManyPanes = tabManager.activeTab.map { $0.paneController.paneTree.paneCount > 1 } ?? false
            return hasManyTabs || hasManyPanes
        case #selector(switchToTab(_:)):
            return menuItem.tag < tabManager.tabs.count
        default:
            return true
        }
    }
}
