// ABOUTME: NSViewRepresentable host container that displays the active tab's terminal view.
// ABOUTME: Swaps the active MetalTerminalView in/out as tabs change, without recreating views.

import SwiftUI

struct TerminalPanel: NSViewRepresentable {
    let tabManager: TerminalTabManager
    var fontFamily: String = ""

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.autoresizesSubviews = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let activeView = tabManager.activeTab?.terminalView else {
            // No active tab — remove all subviews
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        // Only swap if the active view isn't already the sole subview
        if container.subviews.first !== activeView {
            container.subviews.forEach { $0.removeFromSuperview() }
            activeView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(activeView)
            NSLayoutConstraint.activate([
                activeView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                activeView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                activeView.topAnchor.constraint(equalTo: container.topAnchor),
                activeView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        // Apply font family changes to the active view (preserving the current point size)
        let currentSize = activeView.terminalFont.pointSize
        let desired = FontSelection.terminalFont(family: fontFamily, size: currentSize)
        if activeView.terminalFont != desired {
            activeView.terminalFont = desired
        }
    }
}
