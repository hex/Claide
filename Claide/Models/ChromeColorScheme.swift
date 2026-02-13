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

// MARK: - Theme preview for the browser

/// Lightweight preview data extracted from a Ghostty theme file.
struct ThemePreview: Identifiable, Sendable {
    let id: String
    let name: String
    let background: RGB
    let foreground: RGB
    let sampleColors: [RGB]   // palette 1-4 (red, green, yellow, blue)

    var isDark: Bool { background.perceivedBrightness <= 128 }

    /// Parse a theme file's content into a preview. Returns nil if bg or fg is missing.
    static func parse(id: String, content: String) -> ThemePreview? {
        var bg: RGB?
        var fg: RGB?
        var samples: [Int: RGB] = [:]

        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("background") {
                if let hex = extractValue(trimmed) { bg = RGB(hex: hex) }
            } else if trimmed.hasPrefix("foreground") {
                if let hex = extractValue(trimmed) { fg = RGB(hex: hex) }
            } else if trimmed.hasPrefix("palette") {
                if let (idx, hex) = extractPaletteEntry(trimmed), (1...4).contains(idx) {
                    samples[idx] = RGB(hex: hex)
                }
            }
        }

        guard let background = bg, let foreground = fg else { return nil }
        let sampleColors = (1...4).compactMap { samples[$0] }
        return ThemePreview(
            id: id, name: id,
            background: background, foreground: foreground,
            sampleColors: sampleColors
        )
    }

    // MARK: - Static collections

    static let hexed: ThemePreview = {
        let h = ChromeColorScheme.hexed
        return ThemePreview(
            id: h.id, name: h.name,
            background: h.background, foreground: h.foreground,
            sampleColors: Array(h.ansi[1...4])
        )
    }()

    static let ghosttyThemes: [ThemePreview] = {
        guard let themesURL = Bundle.main.url(
            forResource: "ghostty", withExtension: nil
        )?.appendingPathComponent("themes") else { return [] }

        let names = (try? FileManager.default.contentsOfDirectory(atPath: themesURL.path)) ?? []
        return names.sorted().compactMap { name in
            let url = themesURL.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else { return nil }
            return parse(id: name, content: content)
        }
    }()

    static let darkThemes: [ThemePreview] = ghosttyThemes.filter(\.isDark)
    static let lightThemes: [ThemePreview] = ghosttyThemes.filter { !$0.isDark }

    // MARK: - Private parsing helpers

    /// Extract value after "=" in "key = value".
    private static func extractValue(_ line: String) -> String? {
        guard let eqIdx = line.firstIndex(of: "=") else { return nil }
        let value = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Extract palette index and hex from "palette = N=#RRGGBB".
    private static func extractPaletteEntry(_ line: String) -> (Int, String)? {
        guard let value = extractValue(line) else { return nil }
        let parts = value.split(separator: "=", maxSplits: 1)
        guard parts.count == 2,
              let idx = Int(parts[0]) else { return nil }
        return (idx, String(parts[1]))
    }
}
