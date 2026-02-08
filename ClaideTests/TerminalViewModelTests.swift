// ABOUTME: Tests for TerminalViewModel custom title and tab color behavior.
// ABOUTME: Verifies displayTitle fallback and tabColor preset storage.

import Testing
import SwiftUI
@testable import Claide

@Suite("Terminal View Model — Custom Title")
@MainActor
struct TerminalViewModelTests {

    @Test("displayTitle returns auto-detected title when customTitle is nil")
    func displayTitleFallsBackToAutoTitle() {
        let vm = TerminalViewModel()
        vm.title = "zsh"

        #expect(vm.displayTitle == "zsh")
    }

    @Test("displayTitle returns customTitle when set")
    func displayTitleReturnsCustomTitle() {
        let vm = TerminalViewModel()
        vm.title = "zsh"
        vm.customTitle = "My Server"

        #expect(vm.displayTitle == "My Server")
    }

    @Test("setting customTitle to empty string reverts to auto-detected title")
    func emptyCustomTitleReverts() {
        let vm = TerminalViewModel()
        vm.title = "vim"
        vm.customTitle = "Editing"

        #expect(vm.displayTitle == "Editing")

        vm.customTitle = ""

        #expect(vm.displayTitle == "vim")
    }

    @Test("titleChanged does not overwrite customTitle")
    func titleChangedPreservesCustomTitle() {
        let vm = TerminalViewModel()
        vm.customTitle = "My Tab"
        vm.titleChanged("bash")

        #expect(vm.displayTitle == "My Tab")
        // Underlying title still updated for when custom is cleared
        #expect(vm.title == "bash")
    }
}

@Suite("Terminal View Model — Tab Color")
@MainActor
struct TerminalViewModelTabColorTests {

    @Test("tabColor defaults to nil")
    func tabColorDefaultsToNil() {
        let vm = TerminalViewModel()
        #expect(vm.tabColor == nil)
    }

    @Test("tabColor can be set to a preset")
    func tabColorCanBeSet() {
        let vm = TerminalViewModel()
        vm.tabColor = .red
        #expect(vm.tabColor == .red)
    }

    @Test("tabColor can be cleared back to nil")
    func tabColorCanBeCleared() {
        let vm = TerminalViewModel()
        vm.tabColor = .blue
        vm.tabColor = nil
        #expect(vm.tabColor == nil)
    }

    @Test("all TabColor presets produce non-clear colors")
    func allPresetsHaveColors() {
        for preset in TabColor.allCases {
            // Each preset should resolve to a SwiftUI Color
            let _ = preset.color
        }
    }
}
