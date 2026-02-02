// ABOUTME: Tests for monospaced font enumeration and font creation helpers.
// ABOUTME: Validates filtering, fallback behavior, and NSFont construction.

import Testing
import AppKit
@testable import Claide

@Suite("Font Selection")
struct FontSelectionTests {

    @Test("Monospaced font list includes Menlo and Monaco")
    func monospacedListIncludesKnownFonts() {
        let families = FontSelection.monospacedFamilies()
        #expect(families.contains("Menlo"))
        #expect(families.contains("Monaco"))
    }

    @Test("Monospaced font list is sorted alphabetically")
    func monospacedListIsSorted() {
        let families = FontSelection.monospacedFamilies()
        #expect(families == families.sorted())
    }

    @Test("Monospaced font list excludes proportional fonts")
    func monospacedListExcludesProportional() {
        let families = FontSelection.monospacedFamilies()
        // Helvetica is always present on macOS and is proportional
        #expect(!families.contains("Helvetica"))
    }

    @Test("Terminal font with empty family returns system monospaced")
    func terminalFontEmptyFamily() {
        let font = FontSelection.terminalFont(family: "", size: 14)
        #expect(font == NSFont.monospacedSystemFont(ofSize: 14, weight: .regular))
    }

    @Test("Terminal font with valid family returns that font")
    func terminalFontValidFamily() {
        let font = FontSelection.terminalFont(family: "Menlo", size: 14)
        #expect(font.familyName == "Menlo")
        #expect(font.pointSize == 14)
    }

    @Test("Terminal font with invalid family falls back to system monospaced")
    func terminalFontInvalidFamily() {
        let font = FontSelection.terminalFont(family: "NonExistentFont99", size: 14)
        #expect(font == NSFont.monospacedSystemFont(ofSize: 14, weight: .regular))
    }
}
