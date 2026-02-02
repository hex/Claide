// ABOUTME: Terminal color palette extracted from iTerm2's default profile (Snazzy variant).
// ABOUTME: Applies foreground, background, cursor, selection, and 16 ANSI colors to a SwiftTerm view.

import AppKit
import SwiftTerm

enum TerminalTheme {
    static let foreground  = Palette.nsColor(.fgTerminal)
    static let background  = Palette.nsColor(.bgTerminal)
    static let cursor      = Palette.nsColor(.cursor)
    static let cursorText  = Palette.nsColor(.cursorText)
    static let selection   = Palette.nsColor(.selection)

    // ANSI 0-15 (Snazzy palette)
    nonisolated(unsafe) static let ansiColors: [SwiftTerm.Color] = [
        Palette.termColor(.black),       // 0  black
        Palette.termColor(.red),         // 1  red
        Palette.termColor(.green),       // 2  green
        Palette.termColor(.yellow),      // 3  yellow
        Palette.termColor(.blue),        // 4  blue
        Palette.termColor(.magenta),     // 5  magenta
        Palette.termColor(.cyan),        // 6  cyan
        Palette.termColor(.white),       // 7  white
        Palette.termColor(.brightBlack), // 8  bright black
        Palette.termColor(.red),         // 9  bright red
        Palette.termColor(.green),       // 10 bright green
        Palette.termColor(.yellow),      // 11 bright yellow
        Palette.termColor(.blue),        // 12 bright blue
        Palette.termColor(.magenta),     // 13 bright magenta
        Palette.termColor(.cyan),        // 14 bright cyan
        Palette.termColor(.white),       // 15 bright white
    ]

    static func apply(to view: TerminalView) {
        view.nativeForegroundColor = foreground
        view.nativeBackgroundColor = background
        view.caretColor = cursor
        view.caretTextColor = cursorText
        view.selectedTextBackgroundColor = selection
        view.installColors(ansiColors)
    }
}
