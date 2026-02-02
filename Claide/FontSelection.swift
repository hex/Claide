// ABOUTME: Monospaced font enumeration and creation for terminal and graph views.
// ABOUTME: Filters system fonts to fixed-pitch families with safe fallback to system monospace.

import AppKit

enum FontSelection {

    /// All installed monospaced font families, sorted alphabetically.
    static func monospacedFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { family in
                guard let font = NSFont(name: family, size: 12) else { return false }
                return font.isFixedPitch
            }
            .sorted()
    }

    /// Create an NSFont for the terminal from a family name.
    /// Empty or invalid family falls back to system monospaced.
    static func terminalFont(family: String, size: CGFloat) -> NSFont {
        if !family.isEmpty, let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
