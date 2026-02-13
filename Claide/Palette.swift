// ABOUTME: Single source of truth for all colors as 8-bit RGB values.
// ABOUTME: Conversion functions produce SwiftUI Color and NSColor from one definition.

import AppKit
import SwiftUI

/// 8-bit RGB color value. Static members define the app-wide palette.
struct RGB: Equatable, Hashable, Sendable {
    let r: UInt8, g: UInt8, b: UInt8
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        self.r = UInt8(round(c.redComponent * 255))
        self.g = UInt8(round(c.greenComponent * 255))
        self.b = UInt8(round(c.blueComponent * 255))
    }

    /// Parse a hex color string like "#RRGGBB" or "RRGGBB".
    init?(hex: String) {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let value = UInt32(h, radix: 16) else { return nil }
        self.r = UInt8((value >> 16) & 0xFF)
        self.g = UInt8((value >> 8) & 0xFF)
        self.b = UInt8(value & 0xFF)
    }

    /// ITU-R BT.601 luma: 0 (black) to 255 (white).
    var perceivedBrightness: Int {
        (Int(r) * 299 + Int(g) * 587 + Int(b) * 114) / 1000
    }

    /// Hex string like "#1a1b26" for use in terminal config APIs.
    var hexString: String {
        String(format: "#%02x%02x%02x", r, g, b)
    }
}

// MARK: - Palette entries

extension RGB {

    // -- Backgrounds (darkest to lightest) --
    static let bgPrimary  = RGB(15, 18, 23)
    static let bgPanel    = RGB(20, 23, 31)
    static let bgSunken   = RGB(13, 15, 20)
    static let bgHover    = RGB(31, 33, 41)
    static let bgTerminal = RGB(21, 23, 40)

    // -- Foreground / Text --
    static let fgPrimary   = RGB(224, 230, 235)
    static let fgSecondary = RGB(128, 135, 148)
    static let fgMuted     = RGB(89, 97, 107)
    static let fgTerminal  = RGB(239, 240, 235)

    // -- Borders / Edges --
    static let border    = RGB(46, 51, 61)
    static let edgeMuted = RGB(77, 84, 97)

    // -- Hexed ANSI (bright/neon, for terminal) --
    static let black       = RGB(0, 0, 0)
    static let red         = RGB(255, 92, 87)
    static let green       = RGB(90, 247, 142)
    static let yellow      = RGB(243, 249, 157)
    static let blue        = RGB(87, 199, 255)
    static let magenta     = RGB(255, 106, 193)
    static let cyan        = RGB(154, 237, 254)
    static let white       = RGB(241, 241, 240)
    static let brightBlack = RGB(104, 104, 104)

    // -- UI chromatic (muted/saturated, for badges and status) --
    static let uiRed    = RGB(230, 77, 77)
    static let uiGreen  = RGB(77, 191, 115)
    static let uiYellow = RGB(230, 191, 51)
    static let uiBlue   = RGB(77, 140, 242)
    static let uiOrange = RGB(242, 153, 51)

    // -- Priority --
    static let priCritical = RGB(242, 64, 64)
    static let priMedium   = RGB(230, 204, 64)
    static let priLow      = RGB(89, 153, 242)
    static let priBacklog  = RGB(115, 122, 133)

    // -- Issue types --
    static let typeBug     = RGB(159, 32, 17)
    static let typeTask    = RGB(205, 158, 51)
    static let typeEpic    = RGB(246, 152, 66)
    static let typeFeature = RGB(81, 203, 67)
    static let typeChore   = RGB(102, 102, 102)
}

// MARK: - Conversions

enum Palette {
    static func color(_ rgb: RGB) -> SwiftUI.Color {
        SwiftUI.Color(
            red: Double(rgb.r) / 255,
            green: Double(rgb.g) / 255,
            blue: Double(rgb.b) / 255
        )
    }

    static func nsColor(_ rgb: RGB) -> NSColor {
        NSColor(
            srgbRed: CGFloat(rgb.r) / 255,
            green: CGFloat(rgb.g) / 255,
            blue: CGFloat(rgb.b) / 255,
            alpha: 1
        )
    }
}
