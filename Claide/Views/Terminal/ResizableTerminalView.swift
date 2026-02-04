// ABOUTME: LocalProcessTerminalView subclass that reflows the terminal grid on AppKit resizes.
// ABOUTME: Fixes SwiftTerm's setFrameSize not calling processSizeChange.

import SwiftTerm
import AppKit

final class ResizableTerminalView: LocalProcessTerminalView {
    private var isUpdatingFrame = false

    override func setFrameSize(_ newSize: NSSize) {
        guard !isUpdatingFrame else {
            super.setFrameSize(newSize)
            return
        }
        isUpdatingFrame = true
        // The frame setter's didSet calls processSizeChange by comparing oldValue vs new.
        // We must NOT call super.setFrameSize first — that would update the internal size
        // before the setter captures oldValue, making the comparison a no-op.
        frame = NSRect(origin: frame.origin, size: newSize)
        isUpdatingFrame = false
    }
}
