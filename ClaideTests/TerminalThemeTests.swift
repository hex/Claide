// ABOUTME: Tests that the terminal theme applies the correct colors to SwiftTerm views.
// ABOUTME: Verifies foreground, background, cursor, and selection colors match the expected palette.

import Testing
import AppKit
import SwiftTerm
@testable import Claide

@Suite("Terminal Theme")
@MainActor
struct TerminalThemeTests {

    @Test("Apply sets foreground color")
    func applySetsForground() {
        let view = ResizableTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        TerminalTheme.apply(to: view)

        let fg = view.nativeForegroundColor.usingColorSpace(.sRGB)!
        #expect(Int(round(fg.redComponent * 255)) == 239)
        #expect(Int(round(fg.greenComponent * 255)) == 240)
        #expect(Int(round(fg.blueComponent * 255)) == 235)
    }

    @Test("Apply sets background color")
    func applySetsBackground() {
        let view = ResizableTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        TerminalTheme.apply(to: view)

        let bg = view.nativeBackgroundColor.usingColorSpace(.sRGB)!
        #expect(Int(round(bg.redComponent * 255)) == 21)
        #expect(Int(round(bg.greenComponent * 255)) == 23)
        #expect(Int(round(bg.blueComponent * 255)) == 40)
    }

    @Test("Apply sets cursor color")
    func applySetsCursor() {
        let view = ResizableTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        TerminalTheme.apply(to: view)

        let caret = view.caretColor.usingColorSpace(.sRGB)!
        #expect(Int(round(caret.redComponent * 255)) == 234)
        #expect(Int(round(caret.greenComponent * 255)) == 234)
        #expect(Int(round(caret.blueComponent * 255)) == 234)
    }

    @Test("Apply sets selection color")
    func applySetsSelection() {
        let view = ResizableTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        TerminalTheme.apply(to: view)

        let sel = view.selectedTextBackgroundColor.usingColorSpace(.sRGB)!
        #expect(Int(round(sel.redComponent * 255)) == 131)
        #expect(Int(round(sel.greenComponent * 255)) == 74)
        #expect(Int(round(sel.blueComponent * 255)) == 136)
    }
}
