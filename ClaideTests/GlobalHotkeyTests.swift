// ABOUTME: Tests for Carbon hotkey modifier conversion and registration lifecycle.
// ABOUTME: Verifies round-trip between NSEvent.ModifierFlags and Carbon modifier bitmask.

import Testing
import AppKit
import Carbon.HIToolbox
@testable import Claide

@Suite("Global Hotkey")
struct GlobalHotkeyTests {

    // MARK: - Modifier Conversion

    @Test("command maps to cmdKey")
    func commandModifier() {
        let carbon = GlobalHotkey.carbonModifiers(from: .command)
        #expect(carbon == UInt32(cmdKey))
    }

    @Test("option maps to optionKey")
    func optionModifier() {
        let carbon = GlobalHotkey.carbonModifiers(from: .option)
        #expect(carbon == UInt32(optionKey))
    }

    @Test("control maps to controlKey")
    func controlModifier() {
        let carbon = GlobalHotkey.carbonModifiers(from: .control)
        #expect(carbon == UInt32(controlKey))
    }

    @Test("shift maps to shiftKey")
    func shiftModifier() {
        let carbon = GlobalHotkey.carbonModifiers(from: .shift)
        #expect(carbon == UInt32(shiftKey))
    }

    @Test("combined modifiers accumulate")
    func combinedModifiers() {
        let flags: NSEvent.ModifierFlags = [.command, .option]
        let carbon = GlobalHotkey.carbonModifiers(from: flags)
        #expect(carbon == UInt32(cmdKey) | UInt32(optionKey))
    }

    @Test("empty modifiers produce zero")
    func emptyModifiers() {
        let carbon = GlobalHotkey.carbonModifiers(from: [])
        #expect(carbon == 0)
    }

    // MARK: - Round-trip Conversion

    @Test("cocoa to carbon round-trip preserves modifiers")
    func roundTrip() {
        let original: NSEvent.ModifierFlags = [.control, .shift]
        let carbon = GlobalHotkey.carbonModifiers(from: original)
        let back = GlobalHotkey.cocoaModifiers(from: carbon)
        #expect(back == original)
    }

    @Test("all four modifiers round-trip")
    func allModifiersRoundTrip() {
        let original: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let carbon = GlobalHotkey.carbonModifiers(from: original)
        let back = GlobalHotkey.cocoaModifiers(from: carbon)
        #expect(back == original)
    }
}
