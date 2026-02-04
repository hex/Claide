// ABOUTME: Terminal color palette extracted from iTerm2's default profile (Snazzy variant).
// ABOUTME: Provides named color constants for the terminal background, cursor, and ANSI colors.

import AppKit

enum TerminalTheme {
    static let foreground  = Palette.nsColor(.fgTerminal)
    static let background  = Palette.nsColor(.bgTerminal)
    static let cursor      = Palette.nsColor(.cursor)
    static let cursorText  = Palette.nsColor(.cursorText)
    static let selection   = Palette.nsColor(.selection)
}
