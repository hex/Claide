// ABOUTME: Manages an NSSplitView hierarchy that mirrors a PaneNode tree.
// ABOUTME: Rebuilds the view hierarchy on tree changes, preserving terminal view instances.

import AppKit

final class PaneContainerView: NSView {

    /// Current pane-to-view mapping, populated during applyTree.
    private var paneViews: [PaneID: NSView] = [:]

    /// Rebuild the view hierarchy to match the given pane tree.
    ///
    /// The `viewProvider` closure supplies the NSView for each terminal pane ID.
    /// Views are detached (not destroyed) before rebuilding, so MetalTerminalView
    /// instances survive across tree changes.
    func applyTree(_ tree: PaneNode, viewProvider: (PaneID) -> NSView?) {
        subviews.forEach { $0.removeFromSuperview() }
        paneViews.removeAll()

        let root = buildView(for: tree, viewProvider: viewProvider)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Look up the view for a given pane ID.
    func paneView(for id: PaneID) -> NSView? {
        paneViews[id]
    }

    // MARK: - Private

    private func buildView(for node: PaneNode, viewProvider: (PaneID) -> NSView?) -> NSView {
        switch node {
        case .terminal(let id):
            if let view = viewProvider(id) {
                paneViews[id] = view
                return view
            }
            return NSView()

        case .split(let axis, let first, let second):
            let split = PaneSplitView()
            // horizontal axis = side-by-side panes = vertical divider
            split.isVertical = (axis == .horizontal)

            let firstView = buildView(for: first, viewProvider: viewProvider)
            let secondView = buildView(for: second, viewProvider: viewProvider)
            split.addArrangedSubview(firstView)
            split.addArrangedSubview(secondView)

            return split
        }
    }
}
