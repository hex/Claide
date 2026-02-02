// ABOUTME: Tests that ResizableTerminalView reflows the terminal grid on setFrameSize.
// ABOUTME: Verifies the fix for SwiftTerm's setFrameSize not calling processSizeChange.

import Testing
import AppKit
import SwiftTerm
@testable import Claide

@Suite("Resizable Terminal View")
@MainActor
struct ResizableTerminalViewTests {

    @Test("setFrameSize updates terminal cols and rows")
    func setFrameSizeUpdatesGrid() {
        let initialFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let view = ResizableTerminalView(frame: initialFrame)

        let initialDims = view.getTerminal().getDims()

        // Resize via setFrameSize (the AppKit path during window/split resize)
        let smallerSize = NSSize(width: 400, height: 300)
        view.setFrameSize(smallerSize)

        let newDims = view.getTerminal().getDims()

        #expect(newDims.cols < initialDims.cols, "Cols should decrease when width shrinks")
        #expect(newDims.rows < initialDims.rows, "Rows should decrease when height shrinks")
    }

    @Test("setFrameSize with larger size increases grid dimensions")
    func setFrameSizeIncreasesGrid() {
        let initialFrame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let view = ResizableTerminalView(frame: initialFrame)

        let initialDims = view.getTerminal().getDims()

        view.setFrameSize(NSSize(width: 800, height: 600))

        let newDims = view.getTerminal().getDims()

        #expect(newDims.cols > initialDims.cols, "Cols should increase when width grows")
        #expect(newDims.rows > initialDims.rows, "Rows should increase when height grows")
    }
}
