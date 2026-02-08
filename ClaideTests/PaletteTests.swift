// ABOUTME: Tests that Palette RGB entries convert correctly to SwiftUI Color and NSColor.
// ABOUTME: Verifies round-trip fidelity and that specific palette entries hold expected values.

import Testing
import AppKit
@testable import Claide

@Suite("Palette")
struct PaletteTests {

    // MARK: - RGB struct

    @Test("RGB stores components")
    func rgbStoresComponents() {
        let c = RGB(42, 128, 255)
        #expect(c.r == 42)
        #expect(c.g == 128)
        #expect(c.b == 255)
    }

    @Test("RGB equality")
    func rgbEquality() {
        #expect(RGB(10, 20, 30) == RGB(10, 20, 30))
        #expect(RGB(10, 20, 30) != RGB(10, 20, 31))
    }

    // MARK: - NSColor conversion

    @Test("nsColor produces correct sRGB components")
    func nsColorConversion() {
        let ns = Palette.nsColor(.bgPrimary)
        let srgb = ns.usingColorSpace(.sRGB)!
        #expect(Int(round(srgb.redComponent * 255)) == 15)
        #expect(Int(round(srgb.greenComponent * 255)) == 18)
        #expect(Int(round(srgb.blueComponent * 255)) == 23)
    }

    @Test("nsColor for terminal foreground matches expected values")
    func nsColorTerminalForeground() {
        let ns = Palette.nsColor(.fgTerminal)
        let srgb = ns.usingColorSpace(.sRGB)!
        #expect(Int(round(srgb.redComponent * 255)) == 239)
        #expect(Int(round(srgb.greenComponent * 255)) == 240)
        #expect(Int(round(srgb.blueComponent * 255)) == 235)
    }

    // MARK: - SwiftUI Color conversion

    @Test("color produces matching NSColor components")
    @MainActor
    func colorConversion() {
        let c = Palette.color(.fgPrimary)
        let ns = NSColor(c).usingColorSpace(.sRGB)!
        #expect(Int(round(ns.redComponent * 255)) == 224)
        #expect(Int(round(ns.greenComponent * 255)) == 230)
        #expect(Int(round(ns.blueComponent * 255)) == 235)
    }

    // MARK: - Specific palette entries

    @Test("Background entries hold correct values")
    func backgroundEntries() {
        #expect(RGB.bgPrimary == RGB(15, 18, 23))
        #expect(RGB.bgPanel == RGB(20, 23, 31))
        #expect(RGB.bgSunken == RGB(13, 15, 20))
        #expect(RGB.bgHover == RGB(31, 33, 41))
        #expect(RGB.bgTerminal == RGB(21, 23, 40))
    }

    @Test("Hexed ANSI entries hold correct values")
    func hexedEntries() {
        #expect(RGB.red == RGB(255, 92, 87))
        #expect(RGB.green == RGB(90, 247, 142))
        #expect(RGB.yellow == RGB(243, 249, 157))
        #expect(RGB.blue == RGB(87, 199, 255))
        #expect(RGB.magenta == RGB(255, 106, 193))
        #expect(RGB.cyan == RGB(154, 237, 254))
    }

    @Test("UI chromatic entries hold correct values")
    func uiEntries() {
        #expect(RGB.uiRed == RGB(230, 77, 77))
        #expect(RGB.uiGreen == RGB(77, 191, 115))
        #expect(RGB.uiYellow == RGB(230, 191, 51))
        #expect(RGB.uiBlue == RGB(77, 140, 242))
    }

    @Test("Type entries hold correct values")
    func typeEntries() {
        #expect(RGB.typeBug == RGB(159, 32, 17))
        #expect(RGB.typeFeature == RGB(81, 203, 67))
        #expect(RGB.typeChore == RGB(102, 102, 102))
    }
}
