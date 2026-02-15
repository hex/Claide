// ABOUTME: Tests for TmuxKeyEncoder — macOS keycode to tmux send-keys notation.
// ABOUTME: Covers special keys, modifier prefixes, and keycode mapping.

import Testing
import AppKit
@testable import Claide

@Suite("TmuxKeyEncoder — special key mapping")
struct TmuxSpecialKeyTests {

    @Test("Enter key maps to Enter")
    func enterKey() {
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x24) == "Enter")
    }

    @Test("Tab key maps to Tab")
    func tabKey() {
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x30) == "Tab")
    }

    @Test("Backspace maps to BSpace")
    func backspace() {
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x33) == "BSpace")
    }

    @Test("Escape maps to Escape")
    func escape() {
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x35) == "Escape")
    }

    @Test("Arrow keys map correctly")
    func arrowKeys() {
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x7B) == "Left")
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x7C) == "Right")
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x7D) == "Down")
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x7E) == "Up")
    }

    @Test("Navigation keys map correctly")
    func navigationKeys() {
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x73) == "Home")
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x77) == "End")
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x74) == "PageUp")
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x79) == "PageDown")
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x75) == "DC")
    }

    @Test("Function keys F1-F12 map correctly")
    func functionKeys() {
        let expected: [(UInt16, String)] = [
            (0x7A, "F1"), (0x78, "F2"), (0x63, "F3"), (0x76, "F4"),
            (0x60, "F5"), (0x61, "F6"), (0x62, "F7"), (0x64, "F8"),
            (0x65, "F9"), (0x6D, "F10"), (0x67, "F11"), (0x6F, "F12"),
        ]
        for (keyCode, name) in expected {
            #expect(TmuxKeyEncoder.specialKey(keyCode: keyCode) == name)
        }
    }

    @Test("Unknown keycode returns nil")
    func unknownKeycode() {
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0x00) == nil)
        #expect(TmuxKeyEncoder.specialKey(keyCode: 0xFF) == nil)
    }
}

@Suite("TmuxKeyEncoder — modifier prefix")
struct TmuxModifierPrefixTests {

    @Test("No modifiers returns key unchanged")
    func noModifiers() {
        let result = TmuxKeyEncoder.withModifierPrefix([], key: "Enter")
        #expect(result == "Enter")
    }

    @Test("Shift modifier adds S- prefix")
    func shiftPrefix() {
        let result = TmuxKeyEncoder.withModifierPrefix(.shift, key: "F1")
        #expect(result == "S-F1")
    }

    @Test("Option modifier adds M- prefix")
    func optionPrefix() {
        let result = TmuxKeyEncoder.withModifierPrefix(.option, key: "Left")
        #expect(result == "M-Left")
    }

    @Test("Shift+Option adds both prefixes in order")
    func shiftOptionPrefix() {
        let result = TmuxKeyEncoder.withModifierPrefix([.shift, .option], key: "Up")
        #expect(result == "S-M-Up")
    }

    @Test("Command modifier is not included (handled by Claide)")
    func commandNotIncluded() {
        let result = TmuxKeyEncoder.withModifierPrefix(.command, key: "Enter")
        #expect(result == "Enter")
    }
}
