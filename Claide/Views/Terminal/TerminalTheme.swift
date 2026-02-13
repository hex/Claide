// ABOUTME: Terminal color palette for the Hexed color scheme.
// ABOUTME: Provides named color constants for the terminal background, cursor, and ANSI colors.

import AppKit

enum TerminalTheme {
    static let foreground  = Palette.nsColor(.fgTerminal)
    static let cursor      = Palette.nsColor(.cursor)
    static let cursorText  = Palette.nsColor(.cursorText)
    static let selection   = Palette.nsColor(.selection)

    /// Background color read from Ghostty's finalized config so chrome
    /// matches the actual terminal rendering.
    static var background: NSColor {
        GhosttyApp.backgroundColor
    }
}
