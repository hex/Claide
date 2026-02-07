// ABOUTME: Coordinates pane tree mutations, view lifecycle, and focus tracking.
// ABOUTME: Bridges PaneNode data model to PaneContainerView hierarchy.

import AppKit

@MainActor
final class PaneTreeController {

    nonisolated(unsafe) private(set) var paneTree: PaneNode
    let containerView = PaneContainerView()
    nonisolated(unsafe) private(set) var activePaneID: PaneID

    /// Called when a pane's close button is clicked. Set by the tab manager.
    var onPaneCloseRequested: ((PaneID) -> Void)? {
        didSet {
            containerView.onClosePane = { [weak self] id in
                self?.onPaneCloseRequested?(id)
            }
        }
    }

    nonisolated(unsafe) private var paneViews: [PaneID: NSView] = [:]
    private let viewFactory: (PaneID) -> NSView

    /// Create a controller with a single initial pane.
    ///
    /// The `viewFactory` is called each time a new pane is created (initial + splits).
    /// It receives the new pane's ID and must return the NSView to display.
    init(viewFactory: @escaping (PaneID) -> NSView) {
        self.viewFactory = viewFactory
        let initialID = PaneID()
        self.paneTree = .terminal(id: initialID)
        self.activePaneID = initialID

        let view = viewFactory(initialID)
        paneViews[initialID] = view

        rebuildContainer()
    }

    // MARK: - Operations

    /// Split the active pane along the given axis.
    /// Returns the new pane's ID, or nil if the split failed.
    @discardableResult
    func splitActivePane(axis: SplitAxis) -> PaneID? {
        guard let (newTree, newID) = paneTree.splitting(activePaneID, axis: axis) else {
            return nil
        }

        let newView = viewFactory(newID)
        paneViews[newID] = newView
        paneTree = newTree
        activePaneID = newID

        rebuildContainer()
        return newID
    }

    /// Close the pane with the given ID.
    /// Returns true if closed, false if it was the last pane (cannot close).
    @discardableResult
    func closePane(_ paneID: PaneID) -> Bool {
        guard let newTree = paneTree.closing(paneID) else {
            return false
        }

        // Refocus before updating the tree so siblingPaneID still works
        if activePaneID == paneID {
            activePaneID = paneTree.siblingPaneID(of: paneID)
                ?? newTree.allPaneIDs.first!
        }

        paneViews.removeValue(forKey: paneID)
        paneTree = newTree

        rebuildContainer()
        return true
    }

    /// Change focus to the given pane. No-op if the ID is not in the tree.
    func focusPane(_ paneID: PaneID) {
        guard paneTree.contains(id: paneID) else { return }
        activePaneID = paneID
    }

    /// Look up the view for a given pane ID.
    nonisolated func paneView(for paneID: PaneID) -> NSView? {
        paneViews[paneID]
    }

    /// Update the title shown in a pane's title bar.
    func setPaneTitle(_ title: String, for paneID: PaneID) {
        containerView.setTitle(title, for: paneID)
    }

    // MARK: - Private

    private func rebuildContainer() {
        containerView.applyTree(paneTree) { [paneViews] id in
            paneViews[id]
        }
    }
}
