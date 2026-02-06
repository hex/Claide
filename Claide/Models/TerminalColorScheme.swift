// ABOUTME: Terminal color scheme model with built-in presets.
// ABOUTME: Defines 16 ANSI colors, FG/BG, cursor, and selection colors per scheme.

import Foundation

/// A complete terminal color scheme defining all colors needed for rendering.
struct TerminalColorScheme: Identifiable, Hashable {
    let id: String
    let name: String
    let ansi: [RGB]         // 16 ANSI colors (indices 0-15)
    let foreground: RGB
    let background: RGB
    let cursor: RGB
    let cursorText: RGB
    let selection: RGB

    static let builtIn: [TerminalColorScheme] = [
        .snazzy,
        .dracula,
        .nord,
        .catppuccinFrappe,
        .oneDark,
        .gruvboxDark,
        .tokyoNight,
        .solarizedDark,
        .solarizedLight,
    ]

    static let `default` = builtIn[0]

    /// Look up a scheme by id, falling back to the default.
    static func named(_ id: String) -> TerminalColorScheme {
        builtIn.first { $0.id == id } ?? .default
    }

    // MARK: - Snazzy (current default)

    static let snazzy = TerminalColorScheme(
        id: "snazzy",
        name: "Snazzy",
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
        background: RGB(0x15, 0x17, 0x28),
        cursor: RGB(0xea, 0xea, 0xea),
        cursorText: RGB(0x34, 0x37, 0x44),
        selection: RGB(0x83, 0x4a, 0x88)
    )

    // MARK: - Dracula

    static let dracula = TerminalColorScheme(
        id: "dracula",
        name: "Dracula",
        ansi: [
            RGB(0x21, 0x22, 0x2c), // Black
            RGB(0xff, 0x55, 0x55), // Red
            RGB(0x50, 0xfa, 0x7b), // Green
            RGB(0xf1, 0xfa, 0x8c), // Yellow
            RGB(0xbd, 0x93, 0xf9), // Blue
            RGB(0xff, 0x79, 0xc6), // Magenta
            RGB(0x8b, 0xe9, 0xfd), // Cyan
            RGB(0xf8, 0xf8, 0xf2), // White
            RGB(0x62, 0x72, 0xa4), // Bright Black
            RGB(0xff, 0x6e, 0x6e), // Bright Red
            RGB(0x69, 0xff, 0x94), // Bright Green
            RGB(0xff, 0xff, 0xa5), // Bright Yellow
            RGB(0xd6, 0xac, 0xff), // Bright Blue
            RGB(0xff, 0x92, 0xdf), // Bright Magenta
            RGB(0xa4, 0xff, 0xff), // Bright Cyan
            RGB(0xff, 0xff, 0xff), // Bright White
        ],
        foreground: RGB(0xf8, 0xf8, 0xf2),
        background: RGB(0x28, 0x2a, 0x36),
        cursor: RGB(0xf8, 0xf8, 0xf2),
        cursorText: RGB(0x28, 0x2a, 0x36),
        selection: RGB(0x44, 0x47, 0x5a)
    )

    // MARK: - Nord

    static let nord = TerminalColorScheme(
        id: "nord",
        name: "Nord",
        ansi: [
            RGB(0x3b, 0x42, 0x52), // Black
            RGB(0xbf, 0x61, 0x6a), // Red
            RGB(0xa3, 0xbe, 0x8c), // Green
            RGB(0xeb, 0xcb, 0x8b), // Yellow
            RGB(0x81, 0xa1, 0xc1), // Blue
            RGB(0xb4, 0x8e, 0xad), // Magenta
            RGB(0x88, 0xc0, 0xd0), // Cyan
            RGB(0xe5, 0xe9, 0xf0), // White
            RGB(0x4c, 0x56, 0x6a), // Bright Black
            RGB(0xbf, 0x61, 0x6a), // Bright Red
            RGB(0xa3, 0xbe, 0x8c), // Bright Green
            RGB(0xeb, 0xcb, 0x8b), // Bright Yellow
            RGB(0x81, 0xa1, 0xc1), // Bright Blue
            RGB(0xb4, 0x8e, 0xad), // Bright Magenta
            RGB(0x8f, 0xbc, 0xbb), // Bright Cyan
            RGB(0xec, 0xef, 0xf4), // Bright White
        ],
        foreground: RGB(0xd8, 0xde, 0xe9),
        background: RGB(0x2e, 0x34, 0x40),
        cursor: RGB(0xd8, 0xde, 0xe9),
        cursorText: RGB(0x2e, 0x34, 0x40),
        selection: RGB(0x43, 0x4c, 0x5e)
    )

    // MARK: - Catppuccin Frappe

    static let catppuccinFrappe = TerminalColorScheme(
        id: "catppuccin-frappe",
        name: "Catppuccin Frappe",
        ansi: [
            RGB(0x51, 0x57, 0x6d), // Black (Surface 1)
            RGB(0xe7, 0x82, 0x84), // Red
            RGB(0xa6, 0xd1, 0x89), // Green
            RGB(0xe5, 0xc8, 0x90), // Yellow
            RGB(0x8c, 0xaa, 0xee), // Blue
            RGB(0xf4, 0xb8, 0xe4), // Magenta (Pink)
            RGB(0x81, 0xc8, 0xbe), // Cyan (Teal)
            RGB(0xb5, 0xbf, 0xe2), // White (Subtext 1)
            RGB(0x62, 0x68, 0x80), // Bright Black (Surface 2)
            RGB(0xe7, 0x82, 0x84), // Bright Red
            RGB(0xa6, 0xd1, 0x89), // Bright Green
            RGB(0xe5, 0xc8, 0x90), // Bright Yellow
            RGB(0x8c, 0xaa, 0xee), // Bright Blue
            RGB(0xf4, 0xb8, 0xe4), // Bright Magenta
            RGB(0x81, 0xc8, 0xbe), // Bright Cyan
            RGB(0xa5, 0xad, 0xce), // Bright White (Subtext 0)
        ],
        foreground: RGB(0xc6, 0xd0, 0xf5),
        background: RGB(0x30, 0x34, 0x46),
        cursor: RGB(0xf2, 0xd5, 0xcf),
        cursorText: RGB(0x30, 0x34, 0x46),
        selection: RGB(0x41, 0x45, 0x59)
    )

    // MARK: - One Dark

    static let oneDark = TerminalColorScheme(
        id: "one-dark",
        name: "One Dark",
        ansi: [
            RGB(0x28, 0x2c, 0x34), // Black
            RGB(0xe0, 0x6c, 0x75), // Red
            RGB(0x98, 0xc3, 0x79), // Green
            RGB(0xe5, 0xc0, 0x7b), // Yellow
            RGB(0x61, 0xaf, 0xef), // Blue
            RGB(0xc6, 0x78, 0xdd), // Magenta
            RGB(0x56, 0xb6, 0xc2), // Cyan
            RGB(0xab, 0xb2, 0xbf), // White
            RGB(0x54, 0x5b, 0x69), // Bright Black
            RGB(0xe0, 0x6c, 0x75), // Bright Red
            RGB(0x98, 0xc3, 0x79), // Bright Green
            RGB(0xe5, 0xc0, 0x7b), // Bright Yellow
            RGB(0x61, 0xaf, 0xef), // Bright Blue
            RGB(0xc6, 0x78, 0xdd), // Bright Magenta
            RGB(0x56, 0xb6, 0xc2), // Bright Cyan
            RGB(0xff, 0xff, 0xff), // Bright White
        ],
        foreground: RGB(0xab, 0xb2, 0xbf),
        background: RGB(0x28, 0x2c, 0x34),
        cursor: RGB(0x52, 0x8b, 0xff),
        cursorText: RGB(0x28, 0x2c, 0x34),
        selection: RGB(0x3e, 0x44, 0x51)
    )

    // MARK: - Gruvbox Dark

    static let gruvboxDark = TerminalColorScheme(
        id: "gruvbox-dark",
        name: "Gruvbox Dark",
        ansi: [
            RGB(0x28, 0x28, 0x28), // Black (bg0)
            RGB(0xcc, 0x24, 0x1d), // Red
            RGB(0x98, 0x97, 0x1a), // Green
            RGB(0xd7, 0x99, 0x21), // Yellow
            RGB(0x45, 0x85, 0x88), // Blue
            RGB(0xb1, 0x62, 0x86), // Magenta
            RGB(0x68, 0x9d, 0x6a), // Cyan
            RGB(0xa8, 0x99, 0x84), // White (fg4)
            RGB(0x92, 0x83, 0x74), // Bright Black (gray)
            RGB(0xfb, 0x49, 0x34), // Bright Red
            RGB(0xb8, 0xbb, 0x26), // Bright Green
            RGB(0xfa, 0xbd, 0x2f), // Bright Yellow
            RGB(0x83, 0xa5, 0x98), // Bright Blue
            RGB(0xd3, 0x86, 0x9b), // Bright Magenta
            RGB(0x8e, 0xc0, 0x7c), // Bright Cyan
            RGB(0xeb, 0xdb, 0xb2), // Bright White (fg1)
        ],
        foreground: RGB(0xeb, 0xdb, 0xb2),
        background: RGB(0x28, 0x28, 0x28),
        cursor: RGB(0xeb, 0xdb, 0xb2),
        cursorText: RGB(0x28, 0x28, 0x28),
        selection: RGB(0x50, 0x49, 0x45)
    )

    // MARK: - Tokyo Night

    static let tokyoNight = TerminalColorScheme(
        id: "tokyo-night",
        name: "Tokyo Night",
        ansi: [
            RGB(0x15, 0x16, 0x1e), // Black
            RGB(0xf7, 0x76, 0x8e), // Red
            RGB(0x9e, 0xce, 0x6a), // Green
            RGB(0xe0, 0xaf, 0x68), // Yellow
            RGB(0x7a, 0xa2, 0xf7), // Blue
            RGB(0xbb, 0x9a, 0xf7), // Magenta
            RGB(0x7d, 0xcf, 0xff), // Cyan
            RGB(0xa9, 0xb1, 0xd6), // White
            RGB(0x41, 0x48, 0x68), // Bright Black
            RGB(0xf7, 0x76, 0x8e), // Bright Red
            RGB(0x9e, 0xce, 0x6a), // Bright Green
            RGB(0xe0, 0xaf, 0x68), // Bright Yellow
            RGB(0x7a, 0xa2, 0xf7), // Bright Blue
            RGB(0xbb, 0x9a, 0xf7), // Bright Magenta
            RGB(0x7d, 0xcf, 0xff), // Bright Cyan
            RGB(0xc0, 0xca, 0xf5), // Bright White
        ],
        foreground: RGB(0xa9, 0xb1, 0xd6),
        background: RGB(0x1a, 0x1b, 0x26),
        cursor: RGB(0xc0, 0xca, 0xf5),
        cursorText: RGB(0x1a, 0x1b, 0x26),
        selection: RGB(0x28, 0x2d, 0x42)
    )

    // MARK: - Solarized Dark

    static let solarizedDark = TerminalColorScheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        ansi: [
            RGB(0x07, 0x36, 0x42), // Black (base02)
            RGB(0xdc, 0x32, 0x2f), // Red
            RGB(0x85, 0x99, 0x00), // Green
            RGB(0xb5, 0x89, 0x00), // Yellow
            RGB(0x26, 0x8b, 0xd2), // Blue
            RGB(0xd3, 0x36, 0x82), // Magenta
            RGB(0x2a, 0xa1, 0x98), // Cyan
            RGB(0xee, 0xe8, 0xd5), // White (base2)
            RGB(0x00, 0x2b, 0x36), // Bright Black (base03)
            RGB(0xcb, 0x4b, 0x16), // Bright Red (orange)
            RGB(0x58, 0x6e, 0x75), // Bright Green (base01)
            RGB(0x65, 0x7b, 0x83), // Bright Yellow (base00)
            RGB(0x83, 0x94, 0x96), // Bright Blue (base0)
            RGB(0x6c, 0x71, 0xc4), // Bright Magenta (violet)
            RGB(0x93, 0xa1, 0xa1), // Bright Cyan (base1)
            RGB(0xfd, 0xf6, 0xe3), // Bright White (base3)
        ],
        foreground: RGB(0x83, 0x94, 0x96),
        background: RGB(0x00, 0x2b, 0x36),
        cursor: RGB(0x83, 0x94, 0x96),
        cursorText: RGB(0x00, 0x2b, 0x36),
        selection: RGB(0x07, 0x36, 0x42)
    )

    // MARK: - Solarized Light

    static let solarizedLight = TerminalColorScheme(
        id: "solarized-light",
        name: "Solarized Light",
        ansi: [
            RGB(0xee, 0xe8, 0xd5), // Black (base2)
            RGB(0xdc, 0x32, 0x2f), // Red
            RGB(0x85, 0x99, 0x00), // Green
            RGB(0xb5, 0x89, 0x00), // Yellow
            RGB(0x26, 0x8b, 0xd2), // Blue
            RGB(0xd3, 0x36, 0x82), // Magenta
            RGB(0x2a, 0xa1, 0x98), // Cyan
            RGB(0x07, 0x36, 0x42), // White (base02)
            RGB(0xfd, 0xf6, 0xe3), // Bright Black (base3)
            RGB(0xcb, 0x4b, 0x16), // Bright Red (orange)
            RGB(0x93, 0xa1, 0xa1), // Bright Green (base1)
            RGB(0x83, 0x94, 0x96), // Bright Yellow (base0)
            RGB(0x65, 0x7b, 0x83), // Bright Blue (base00)
            RGB(0x6c, 0x71, 0xc4), // Bright Magenta (violet)
            RGB(0x58, 0x6e, 0x75), // Bright Cyan (base01)
            RGB(0x00, 0x2b, 0x36), // Bright White (base03)
        ],
        foreground: RGB(0x65, 0x7b, 0x83),
        background: RGB(0xfd, 0xf6, 0xe3),
        cursor: RGB(0x65, 0x7b, 0x83),
        cursorText: RGB(0xfd, 0xf6, 0xe3),
        selection: RGB(0xee, 0xe8, 0xd5)
    )
}
