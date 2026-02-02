// ABOUTME: Sets the initial divider position of a parent NSSplitView.
// ABOUTME: Workaround for VSplitView ignoring idealHeight on child frames.

import SwiftUI
import AppKit

struct SplitDividerSetter: NSViewRepresentable {
    let ratio: CGFloat
    let vertical: Bool

    init(ratio: CGFloat, vertical: Bool = false) {
        self.ratio = ratio
        self.vertical = vertical
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Delay to ensure the split view is fully laid out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let splitView = findSplitView(from: view) else { return }
            let total = vertical ? splitView.bounds.width : splitView.bounds.height
            guard total > 0 else { return }
            splitView.setPosition(total * ratio, ofDividerAt: 0)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    // NSSplitView.isVertical means the divider is vertical (left-right split).
    // For VSplitView (top-bottom), isVertical == false.
    private func findSplitView(from view: NSView) -> NSSplitView? {
        var current: NSView? = view.superview
        while let parent = current {
            if let split = parent as? NSSplitView, split.isVertical == vertical {
                return split
            }
            current = parent.superview
        }
        return nil
    }
}
