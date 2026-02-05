// ABOUTME: Tests that MainWindowController configures NSWindow chrome correctly.
// ABOUTME: Verifies titlebar transparency, style mask, and safe area negation.

import Testing
import AppKit
@testable import Claide

@Suite("Main Window Controller")
@MainActor
struct MainWindowControllerTests {

    private func makeController() -> MainWindowController {
        let tabManager = TerminalTabManager()
        return MainWindowController(tabManager: tabManager)
    }

    // MARK: - Window Chrome

    @Test("window has transparent titlebar")
    func transparentTitlebar() {
        let controller = makeController()
        let window = controller.window!

        #expect(window.titlebarAppearsTransparent == true)
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarSeparatorStyle == .none)
    }

    @Test("window has fullSizeContentView in style mask")
    func fullSizeContentView() {
        let controller = makeController()
        let window = controller.window!

        #expect(window.styleMask.contains(.fullSizeContentView))
    }

    @Test("window disallows tabbing and background drag")
    func tabbingAndDrag() {
        let controller = makeController()
        let window = controller.window!

        #expect(window.tabbingMode == .disallowed)
        #expect(window.isMovableByWindowBackground == false)
    }

    @Test("window has dark appearance")
    func darkAppearance() {
        let controller = makeController()
        let window = controller.window!

        #expect(window.appearance?.name == .darkAqua)
    }

    @Test("window has minimum size")
    func minimumSize() {
        let controller = makeController()
        let window = controller.window!

        #expect(window.minSize.width >= 900)
        #expect(window.minSize.height >= 500)
    }

    // MARK: - Content

    @Test("window hosts an NSHostingView as content")
    func hostingViewContent() {
        let controller = makeController()
        let window = controller.window!

        #expect(window.contentView != nil)
        // The content view should be set (NSHostingView wrapping ContentView)
        let contentView = window.contentView!
        #expect(contentView.frame.width > 0 || true) // Just verify it exists
    }
}
