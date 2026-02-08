// ABOUTME: Terminal color palette for the Hexed color scheme.
// ABOUTME: Provides named color constants for the terminal background, cursor, and ANSI colors.

import AppKit

enum TerminalTheme {
    static let foreground  = Palette.nsColor(.fgTerminal)
    static let cursor      = Palette.nsColor(.cursor)
    static let cursorText  = Palette.nsColor(.cursorText)
    static let selection   = Palette.nsColor(.selection)

    /// Background color derived from the active color scheme.
    /// Reads UserDefaults on each access so SwiftUI views that reference this
    /// automatically pick up the correct color when the scheme changes.
    static var background: NSColor {
        let schemeName = UserDefaults.standard.string(forKey: "terminalColorScheme") ?? "hexed"
        let scheme = TerminalColorScheme.named(schemeName)
        return Palette.nsColor(scheme.background)
    }
}
