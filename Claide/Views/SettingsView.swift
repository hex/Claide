// ABOUTME: Settings window for user preferences, accessible via Cmd+,.
// ABOUTME: Toolbar-tabbed layout with General, Terminal, Appearance, Hotkey, and About tabs.

import Sparkle
import SwiftUI

struct SettingsView: View {
    let updater: SPUUpdater

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            TerminalSettingsTab()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            HotkeySettingsTab()
                .tabItem { Label("Hotkey", systemImage: "command.square") }
            AboutSettingsTab(updater: updater)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}
