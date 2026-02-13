// ABOUTME: Terminal color palette for chrome theming.
// ABOUTME: Provides foreground color and Ghostty-sourced background for UI elements.

import AppKit

enum TerminalTheme {
    static let foreground  = Palette.nsColor(.fgTerminal)

    /// Background color read from Ghostty's finalized config so chrome
    /// matches the actual terminal rendering.
    static var background: NSColor {
        GhosttyApp.backgroundColor
    }
}
