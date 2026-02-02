// ABOUTME: Application entry point. Configures a chromeless window with transparent title bar.
// ABOUTME: Content extends under the traffic lights for a minimal terminal aesthetic.

import AppKit
import SwiftUI

@main
struct ClaideApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            "cursorStyle": "bar",
            "cursorBlink": true,
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 500)
                .background(WindowConfigurator())
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 700)
        .commands { TerminalTabCommands() }

        Settings {
            SettingsView()
        }
    }
}

struct TerminalTabCommands: Commands {
    @FocusedValue(\.tabManager) private var tabManager

    var body: some Commands {
        CommandMenu("Terminal") {
            Button("New Tab") {
                tabManager?.addTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                tabManager?.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(tabManager == nil || (tabManager?.tabs.count ?? 0) <= 1)

            Divider()

            ForEach(0..<9, id: \.self) { index in
                Button("Tab \(index + 1)") {
                    tabManager?.switchToTab(at: index)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .disabled(tabManager == nil || index >= (tabManager?.tabs.count ?? 0))
            }
        }
    }
}

/// Reaches into the NSWindow to make the title bar transparent and
/// extend content underneath the traffic light buttons.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowConfiguratorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class WindowConfiguratorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.backgroundColor = Palette.nsColor(.bgPrimary)
    }
}
