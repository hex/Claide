// ABOUTME: Converts macOS keyboard events to tmux send-keys notation.
// ABOUTME: Handles special keys, modifier prefixes, and control character encoding.

import AppKit

/// Encodes NSEvents as tmux `send-keys` arguments.
///
/// tmux key notation: `Enter`, `BSpace`, `Left`, `C-c` (Ctrl+c),
/// `M-x` (Alt+x), `S-F1` (Shift+F1). Literal text is single-quoted.
enum TmuxKeyEncoder {

    /// Convert an NSEvent to a tmux key notation string for `send-keys`.
    /// Returns nil if the event can't be meaningfully encoded.
    static func encode(_ event: NSEvent) -> String? {
        // Special keys first (arrows, Enter, function keys, etc.)
        if let special = specialKey(keyCode: event.keyCode) {
            return withModifierPrefix(event.modifierFlags, key: special)
        }

        guard let chars = event.characters, !chars.isEmpty else { return nil }

        // Control+letter: macOS delivers value < 0x20, reconstruct the letter.
        if event.modifierFlags.contains(.control) {
            if let scalar = chars.unicodeScalars.first, scalar.value < 0x20 {
                let letter = Character(UnicodeScalar(scalar.value + 0x40)!)
                return withModifierPrefix(
                    event.modifierFlags.subtracting(.control),
                    key: "C-\(letter)"
                )
            }
        }

        // Regular printable text — single-quote for tmux
        let escaped = chars.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Map macOS virtual key codes to tmux key names.
    static func specialKey(keyCode: UInt16) -> String? {
        switch keyCode {
        case 0x24: return "Enter"
        case 0x30: return "Tab"
        case 0x33: return "BSpace"
        case 0x35: return "Escape"
        case 0x7B: return "Left"
        case 0x7C: return "Right"
        case 0x7D: return "Down"
        case 0x7E: return "Up"
        case 0x73: return "Home"
        case 0x77: return "End"
        case 0x74: return "PageUp"
        case 0x79: return "PageDown"
        case 0x75: return "DC"       // Forward Delete
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default: return nil
        }
    }

    /// Prefix a tmux key name with modifier notation (S- for shift, M- for option).
    static func withModifierPrefix(_ flags: NSEvent.ModifierFlags, key: String) -> String {
        var prefixes: [String] = []
        if flags.contains(.shift)  { prefixes.append("S-") }
        if flags.contains(.option) { prefixes.append("M-") }
        if prefixes.isEmpty { return key }
        return prefixes.joined() + key
    }
}
