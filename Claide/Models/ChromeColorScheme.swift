// ABOUTME: Color scheme model for UI chrome and terminal content theming.
// ABOUTME: Provides Hexed as a custom preset and enumerates bundled Ghostty themes.

import AppKit
import Foundation

/// Color scheme used to style both application chrome (window appearance,
/// pane title bars, dividers) and terminal content (via Ghostty's theme system).
struct ChromeColorScheme: Identifiable, Hashable {
    let id: String
    let name: String
    let ansi: [RGB]         // 16 ANSI colors (indices 0-15), empty for Ghostty themes
    let foreground: RGB
    let background: RGB

    /// Ghostty built-in theme name matching this scheme.
    /// nil means no match — terminal colors are set via individual palette/fg/bg keys.
    var ghosttyThemeName: String? = nil

    static let `default` = hexed

    /// Look up a scheme by id. Returns Hexed for "hexed", otherwise returns
    /// a scheme whose bg/fg reflect the current Ghostty engine colors.
    static func named(_ id: String) -> ChromeColorScheme {
        if id == hexed.id { return hexed }
        return ChromeColorScheme(
            id: id,
            name: id,
            ansi: [],
            foreground: RGB(GhosttyApp.foregroundColor),
            background: RGB(GhosttyApp.backgroundColor),
            ghosttyThemeName: id
        )
    }

    /// Sorted list of Ghostty theme filenames from the app bundle.
    static let ghosttyThemeNames: [String] = {
        guard let themesURL = Bundle.main.url(
            forResource: "ghostty",
            withExtension: nil
        )?.appendingPathComponent("themes") else {
            return []
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: themesURL.path)) ?? []
        return names.sorted()
    }()

    // MARK: - Hexed (default)

    static let hexed = ChromeColorScheme(
        id: "hexed",
        name: "Hexed",
        ansi: [
            RGB(0x00, 0x00, 0x00), // Black
            RGB(0xff, 0x5c, 0x57), // Red
            RGB(0x5a, 0xf7, 0x8e), // Green
            RGB(0xf3, 0xf9, 0x9d), // Yellow
            RGB(0x57, 0xc7, 0xff), // Blue
            RGB(0xff, 0x6a, 0xc1), // Magenta
            RGB(0x9a, 0xed, 0xfe), // Cyan
            RGB(0xf1, 0xf1, 0xf0), // White
            RGB(0x68, 0x68, 0x68), // Bright Black
            RGB(0xff, 0x5c, 0x57), // Bright Red
            RGB(0x5a, 0xf7, 0x8e), // Bright Green
            RGB(0xf3, 0xf9, 0x9d), // Bright Yellow
            RGB(0x57, 0xc7, 0xff), // Bright Blue
            RGB(0xff, 0x6a, 0xc1), // Bright Magenta
            RGB(0x9a, 0xed, 0xfe), // Bright Cyan
            RGB(0xef, 0xf0, 0xeb), // Bright White
        ],
        foreground: RGB(0xef, 0xf0, 0xeb),
        background: RGB(0x15, 0x17, 0x28)
    )
}
