// ABOUTME: Application entry point. Configures a chromeless window with transparent title bar.
// ABOUTME: Content extends under the traffic lights for a minimal terminal aesthetic.

import AppKit
import Sparkle
import SwiftUI

@main
struct ClaideApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        UserDefaults.standard.register(defaults: [
            "cursorStyle": "bar",
            "cursorBlink": true,
            "terminalFontSize": 14.0,
            "uiFontSize": 13.0,
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
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            TerminalTabCommands()
        }

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
    private nonisolated(unsafe) var observers: [Any] = []

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let newWindow { applyChrome(newWindow) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()

        guard let window else { return }
        applyChrome(window)

        // SwiftUI resets window properties on activation and fullscreen transitions.
        // Re-apply after SwiftUI's own handler finishes (async dispatch).
        // Notifications that need a delayed second pass because SwiftUI's
        // window restoration spans multiple run loop cycles.
        let delayedNames: Set<Notification.Name> = [
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didResizeNotification,
            NSWindow.didExitFullScreenNotification,
        ]

        for name: Notification.Name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didMoveNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didResizeNotification,
        ] {
            let needsDelay = delayedNames.contains(name)
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, let window = self.window else { return }
                    self.applyChrome(window)
                    if needsDelay {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                            guard let self, let window = self.window else { return }
                            self.applyChrome(window)
                        }
                    }
                }
            }
            observers.append(observer)
        }
    }

    private func applyChrome(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.backgroundColor = Palette.nsColor(.bgTerminal)

        // Negate the title bar safe area so NSSplitView content extends to the top.
        // SwiftUI's .ignoresSafeArea() doesn't propagate through AppKit-backed views.
        if let cv = window.contentView {
            let titleBarHeight = window.frame.height - window.contentLayoutRect.height
            cv.additionalSafeAreaInsets.top = -titleBarHeight
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
