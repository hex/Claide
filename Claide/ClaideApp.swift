// ABOUTME: Application entry point with NSApplicationDelegateAdaptor for AppKit window management.
// ABOUTME: Keeps Settings scene for Cmd+, while the main window is managed by AppDelegate.

import Sparkle
import SwiftUI

@main
struct ClaideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var commandKeyObserver = CommandKeyObserver()
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        UserDefaults.standard.register(defaults: [
            // General
            "shellPath": "",
            "workingDirectory": "home",
            "customWorkingDirectory": "",
            "scrollbackLines": 2048,
            "newTabPosition": "end",
            "confirmBeforeClosing": true,
            "quitWhenLastWindowCloses": false,
            "bellStyle": "visual",
            // Terminal
            "copyOnSelect": false,
            "pasteOnRightClick": false,
            // Appearance
            "terminalFontSize": 14.0,
            "uiFontSize": 12.0,
            "terminalColorScheme": "hexed",
            "paneFocusIndicator": true,
            "dimUnfocusedPanes": true,
            // Hotkey Window
            "hotkeyEnabled": false,
            "hotkeyKeyCode": -1,
            "hotkeyModifiers": 0,
            "hotkeyPosition": "top",
            "hotkeyScreen": "cursor",
            "hotkeySize": 50.0,
            "hotkeyAnimation": "slide",
            "hotkeyAnimationDuration": 0.2,
            "hotkeyHideOnFocusLoss": true,
            "hotkeyAllSpaces": true,
            "hotkeyShowSidebar": false,
            "hotkeyFloating": true,
        ])
    }

    var body: some Scene {
        Settings {
            SettingsView(updater: updaterController.updater)
                .environment(commandKeyObserver)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
