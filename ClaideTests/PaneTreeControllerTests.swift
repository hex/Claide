// ABOUTME: Tests for PaneTreeController pane management operations.
// ABOUTME: Verifies split, close, focus, and view lookup via the controller.

import Testing
import AppKit
@testable import Claide

@Suite("PaneTreeController")
@MainActor
struct PaneTreeControllerTests {

    // MARK: - Helpers

    /// Create a controller with a test view factory (plain NSViews instead of Metal).
    private func makeController() -> (PaneTreeController, PaneID) {
        var createdViews: [NSView] = []
        let controller = PaneTreeController { _ in
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            createdViews.append(view)
            return view
        }
        return (controller, controller.activePaneID)
    }

    // MARK: - Initial State

    @Test("starts with a single pane that is active")
    func initialState() {
        let (controller, initialID) = makeController()

        #expect(controller.paneTree.paneCount == 1)
        #expect(controller.activePaneID == initialID)
        #expect(controller.paneView(for: initialID) != nil)
    }

    @Test("container view has one subview initially")
    func initialContainerView() {
        let (controller, _) = makeController()

        #expect(controller.containerView.subviews.count == 1)
    }

    // MARK: - Splitting

    @Test("splitting the active pane creates two panes")
    func splitActivePane() {
        let (controller, originalID) = makeController()

        let newID = controller.splitActivePane(axis: .horizontal)

        #expect(newID != nil)
        #expect(controller.paneTree.paneCount == 2)
        #expect(controller.paneTree.contains(id: originalID))
        #expect(controller.paneTree.contains(id: newID!))
    }

    @Test("splitting creates a view for the new pane")
    func splitCreatesView() {
        let (controller, _) = makeController()

        let newID = controller.splitActivePane(axis: .vertical)!

        #expect(controller.paneView(for: newID) != nil)
    }

    @Test("splitting moves focus to the new pane")
    func splitMovesFocus() {
        let (controller, _) = makeController()

        let newID = controller.splitActivePane(axis: .horizontal)!

        #expect(controller.activePaneID == newID)
    }

    @Test("container view has split view after splitting")
    func splitUpdatesContainer() {
        let (controller, _) = makeController()

        _ = controller.splitActivePane(axis: .horizontal)

        // Container should now hold a PaneSplitView
        #expect(controller.containerView.subviews.count == 1)
        #expect(controller.containerView.subviews.first is NSSplitView)
    }

    // MARK: - Closing

    @Test("closing one pane in a two-pane split returns to single pane")
    func closeOnePane() {
        let (controller, originalID) = makeController()
        let newID = controller.splitActivePane(axis: .horizontal)!

        let closed = controller.closePane(newID)

        #expect(closed)
        #expect(controller.paneTree.paneCount == 1)
        #expect(controller.paneTree.contains(id: originalID))
        #expect(!controller.paneTree.contains(id: newID))
    }

    @Test("closing the active pane moves focus to sibling")
    func closingActivePaneRefocuses() {
        let (controller, originalID) = makeController()
        let newID = controller.splitActivePane(axis: .horizontal)!

        // Active is the new pane; close it
        let closed = controller.closePane(newID)

        #expect(closed)
        #expect(controller.activePaneID == originalID)
    }

    @Test("closing the last pane returns false")
    func closingLastPaneFails() {
        let (controller, onlyID) = makeController()

        let closed = controller.closePane(onlyID)

        #expect(!closed)
        #expect(controller.paneTree.paneCount == 1)
    }

    @Test("closing removes the pane view from lookup")
    func closingRemovesView() {
        let (controller, _) = makeController()
        let newID = controller.splitActivePane(axis: .horizontal)!

        _ = controller.closePane(newID)

        #expect(controller.paneView(for: newID) == nil)
    }

    // MARK: - Focus

    @Test("focusPane changes active pane")
    func focusPane() {
        let (controller, originalID) = makeController()
        _ = controller.splitActivePane(axis: .horizontal)

        controller.focusPane(originalID)

        #expect(controller.activePaneID == originalID)
    }

    @Test("focusPane ignores unknown IDs")
    func focusUnknownPane() {
        let (controller, originalID) = makeController()

        controller.focusPane(PaneID())

        #expect(controller.activePaneID == originalID)
    }

    // MARK: - All Pane IDs

    @Test("allPaneIDs matches tree after multiple splits")
    func allPaneIDsAfterSplits() {
        let (controller, first) = makeController()
        let second = controller.splitActivePane(axis: .horizontal)!
        // Focus back to first and split again
        controller.focusPane(first)
        let third = controller.splitActivePane(axis: .vertical)!

        let ids = controller.paneTree.allPaneIDs
        #expect(ids.count == 3)
        #expect(ids.contains(first))
        #expect(ids.contains(second))
        #expect(ids.contains(third))
    }

    // MARK: - N-ary Splits

    @Test("same-axis splits through controller produce flat tree")
    func sameAxisSplitsProduceFlatTree() {
        let (controller, first) = makeController()

        // All horizontal splits from the newest pane
        let second = controller.splitActivePane(axis: .horizontal)!
        let third = controller.splitActivePane(axis: .horizontal)!
        let fourth = controller.splitActivePane(axis: .horizontal)!

        #expect(controller.paneTree.paneCount == 4)

        // Should be a flat split(horizontal, [first, second, third, fourth])
        guard case .split(let axis, let children) = controller.paneTree else {
            Issue.record("expected split node")
            return
        }
        #expect(axis == .horizontal)
        #expect(children.count == 4)

        let ids = controller.paneTree.allPaneIDs
        #expect(ids.contains(first))
        #expect(ids.contains(second))
        #expect(ids.contains(third))
        #expect(ids.contains(fourth))
    }
}
