// ABOUTME: Application delegate that owns the main window and terminal menu.
// ABOUTME: Creates TerminalTabManager and MainWindowController at launch.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var tabManager: TerminalTabManager!
    private var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        tabManager = TerminalTabManager()
        windowController = MainWindowController(tabManager: tabManager)
        windowController.showWindow(nil)

        // SwiftUI builds the main menu asynchronously after launch.
        // Delay so our Terminal menu is appended after SwiftUI's menu is in place.
        DispatchQueue.main.async { self.installTerminalMenu() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController.showWindow(nil)
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

        let closeTab = NSMenuItem(title: "Close Tab", action: #selector(closeTab), keyEquivalent: "w")
        closeTab.target = self
        menu.addItem(closeTab)

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

    // MARK: - Actions

    @objc private func newTab() {
        tabManager.addTab()
    }

    @objc private func closeTab() {
        tabManager.closeActiveTab()
    }

    @objc private func switchToTab(_ sender: NSMenuItem) {
        tabManager.switchToTab(at: sender.tag)
    }
}

// MARK: - Menu Validation

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(closeTab):
            return tabManager.tabs.count > 1
        case #selector(switchToTab(_:)):
            return menuItem.tag < tabManager.tabs.count
        default:
            return true
        }
    }
}
