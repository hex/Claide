// ABOUTME: NSViewRepresentable host container that displays the active tab's pane container.
// ABOUTME: Swaps the active PaneContainerView in/out as tabs change, without recreating views.

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
        guard let paneContainer = tabManager.activeTab?.paneController.containerView else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }

        // Only swap if the pane container changed (tab switch)
        if container.subviews.first !== paneContainer {
            container.subviews.forEach { $0.removeFromSuperview() }
            paneContainer.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(paneContainer)
            NSLayoutConstraint.activate([
                paneContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                paneContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                paneContainer.topAnchor.constraint(equalTo: container.topAnchor),
                paneContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        // Font is managed by Ghostty config — no per-view font assignment needed
    }
}
