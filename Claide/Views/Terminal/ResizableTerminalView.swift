// ABOUTME: LocalProcessTerminalView subclass that reflows the terminal grid on AppKit resizes.
// ABOUTME: Fixes SwiftTerm's setFrameSize not calling processSizeChange.

import SwiftTerm
import AppKit

final class ResizableTerminalView: LocalProcessTerminalView {
    private var isUpdatingFrame = false

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard !isUpdatingFrame else { return }
        isUpdatingFrame = true
        // Triggers the frame property setter which calls processSizeChange internally
        frame = NSRect(origin: frame.origin, size: newSize)
        isUpdatingFrame = false
    }
}
