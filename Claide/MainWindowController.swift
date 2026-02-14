// ABOUTME: Creates and configures the main NSWindow with chromeless terminal styling.
// ABOUTME: Window chrome is set once at creation; fullscreen safe area handled via delegate.

import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {

    let tabManager: TerminalTabManager
    let layout = ToolWindowLayout()
    let paletteManager = CommandPaletteManager()

    init(tabManager: TerminalTabManager) {
        self.tabManager = tabManager
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.backgroundColor = TerminalTheme.background
        let initialScheme = UserDefaults.standard.string(forKey: "terminalColorScheme") ?? "hexed"
        let initialBG = ChromeColorScheme.named(initialScheme).background
        let initialBrightness = (Int(initialBG.r) * 299 + Int(initialBG.g) * 587 + Int(initialBG.b) * 114) / 1000
        window.appearance = NSAppearance(named: initialBrightness > 128 ? .aqua : .darkAqua)
        window.minSize = NSSize(width: 900, height: 500)

        super.init(window: window)

        paletteManager.tabManager = tabManager
        paletteManager.layout = layout
        paletteManager.toggleSidebar = { [weak self] in
            self?.layout.toggleEdge(.right)
        }

        let commandKeyObserver = CommandKeyObserver()
        let host = NSHostingController(
            rootView: ToolWindowHost(
                tabManager: tabManager,
                paletteManager: paletteManager,
                layout: layout,
                commandKeyObserver: commandKeyObserver
            )
            .environment(commandKeyObserver)
        )
        host.sizingOptions = []
        window.contentViewController = host
        window.delegate = self

        negateTitleBarSafeArea(window)

        tabManager.onColorSchemeApplied = { [weak self] in
            guard let window = self?.window else { return }
            window.backgroundColor = TerminalTheme.background
            let schemeName = UserDefaults.standard.string(forKey: "terminalColorScheme") ?? "hexed"
            let bg = ChromeColorScheme.named(schemeName).background
            let brightness = (Int(bg.r) * 299 + Int(bg.g) * 587 + Int(bg.b) * 114) / 1000
            window.appearance = NSAppearance(named: brightness > 128 ? .aqua : .darkAqua)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else { return }
        repositionTrafficLights(window)
    }

    // MARK: - Safe Area

    private func negateTitleBarSafeArea(_ window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let titleBarHeight = window.frame.height - window.contentLayoutRect.height
        contentView.additionalSafeAreaInsets.top = -titleBarHeight
    }

    // MARK: - Traffic Lights

    /// Shift the traffic light buttons down to vertically center with the tab bar.
    private func repositionTrafficLights(_ window: NSWindow) {
        let verticalOffset: CGFloat = 3
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            var origin = button.frame.origin
            origin.y -= verticalOffset
            button.setFrameOrigin(origin)
        }
    }

    // MARK: - Command Palette

    func toggleCommandPalette() {
        paletteManager.toggle()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard UserDefaults.standard.bool(forKey: "confirmBeforeClosing") else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Close Window?"
        alert.informativeText = "Running processes may be terminated."
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window else { return }
        negateTitleBarSafeArea(window)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window else { return }
        negateTitleBarSafeArea(window)
        repositionTrafficLights(window)
    }
}
