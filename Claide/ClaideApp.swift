// ABOUTME: Application entry point with NSApplicationDelegateAdaptor for AppKit window management.
// ABOUTME: Keeps Settings scene for Cmd+, while the main window is managed by AppDelegate.

import SwiftUI

@main
struct ClaideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        UserDefaults.standard.register(defaults: [
            "cursorStyle": "bar",
            "cursorBlink": true,
            "terminalFontSize": 14.0,
            "uiFontSize": 12.0,
            "terminalColorScheme": "hexed",
            "paneFocusIndicator": true,
            "dimUnfocusedPanes": true,
        ])
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
