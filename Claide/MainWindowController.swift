// ABOUTME: Creates and configures the main NSWindow with chromeless terminal styling.
// ABOUTME: Window chrome is set once at creation; fullscreen safe area handled via delegate.

import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {

    init(tabManager: TerminalTabManager) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.backgroundColor = Palette.nsColor(.bgTerminal)
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 900, height: 500)
        window.setFrameAutosaveName("ClaideMainWindow")

        let hostingView = NSHostingView(
            rootView: ContentView(tabManager: tabManager)
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        )
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self

        negateTitleBarSafeArea(window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - Safe Area

    private func negateTitleBarSafeArea(_ window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let titleBarHeight = window.frame.height - window.contentLayoutRect.height
        contentView.additionalSafeAreaInsets.top = -titleBarHeight
    }

    // MARK: - NSWindowDelegate

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window else { return }
        negateTitleBarSafeArea(window)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window else { return }
        negateTitleBarSafeArea(window)
    }
}
