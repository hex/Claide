// ABOUTME: Tests for PaneContainerView hierarchy management.
// ABOUTME: Verifies view construction from PaneNode trees.

import Testing
import AppKit
@testable import Claide

@Suite("PaneContainerView")
@MainActor
struct PaneContainerViewTests {

    // MARK: - Helpers

    /// Create a plain NSView as a stand-in for MetalTerminalView.
    private func testView() -> NSView {
        NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    }

    // MARK: - Single Pane

    @Test("single pane places view directly as subview")
    func singlePane() {
        let container = PaneContainerView()
        let id = PaneID()
        let view = testView()

        container.applyTree(.terminal(id: id)) { paneID in
            paneID == id ? view : nil
        }

        #expect(container.subviews.count == 1)
        #expect(container.subviews.first === view)
    }

    // MARK: - Two Panes

    @Test("horizontal split creates NSSplitView with vertical divider")
    func horizontalSplit() {
        let container = PaneContainerView()
        let a = PaneID(), b = PaneID()
        let viewA = testView(), viewB = testView()
        let tree = PaneNode.split(axis: .horizontal, children: [.terminal(id: a), .terminal(id: b)])

        container.applyTree(tree) { paneID in
            paneID == a ? viewA : viewB
        }

        #expect(container.subviews.count == 1)
        let splitView = container.subviews.first as? NSSplitView
        #expect(splitView != nil)
        #expect(splitView?.arrangedSubviews.count == 2)
        // horizontal axis = panes side-by-side = vertical divider
        #expect(splitView?.isVertical == true)
    }

    @Test("vertical split creates NSSplitView with horizontal divider")
    func verticalSplit() {
        let container = PaneContainerView()
        let a = PaneID(), b = PaneID()
        let tree = PaneNode.split(axis: .vertical, children: [.terminal(id: a), .terminal(id: b)])

        container.applyTree(tree) { _ in testView() }

        let splitView = container.subviews.first as? NSSplitView
        #expect(splitView != nil)
        // vertical axis = panes stacked = horizontal divider
        #expect(splitView?.isVertical == false)
    }

    // MARK: - N-ary Split

    @Test("n-ary split creates NSSplitView with N children")
    func nArySplit() {
        let container = PaneContainerView()
        let ids = (0..<4).map { _ in PaneID() }
        var views: [PaneID: NSView] = [:]
        for id in ids { views[id] = testView() }

        let tree = PaneNode.split(axis: .horizontal, children: ids.map { .terminal(id: $0) })

        container.applyTree(tree) { views[$0] }

        #expect(container.subviews.count == 1)
        let splitView = container.subviews.first as? NSSplitView
        #expect(splitView != nil)
        #expect(splitView?.arrangedSubviews.count == 4)
    }

    // MARK: - Nested Split

    @Test("nested split creates correct hierarchy")
    func nestedSplit() {
        let container = PaneContainerView()
        let a = PaneID(), b = PaneID(), c = PaneID()
        var views: [PaneID: NSView] = [:]
        views[a] = testView()
        views[b] = testView()
        views[c] = testView()

        // Tree: split(horizontal, [a, split(vertical, [b, c])])
        let inner = PaneNode.split(axis: .vertical, children: [.terminal(id: b), .terminal(id: c)])
        let tree = PaneNode.split(axis: .horizontal, children: [.terminal(id: a), inner])

        container.applyTree(tree) { views[$0] }

        // Root: one split view
        #expect(container.subviews.count == 1)
        let outer = container.subviews.first as? NSSplitView
        #expect(outer?.arrangedSubviews.count == 2)

        // First child: view A (wrapped with close button when paneCount > 1)
        #expect(container.paneView(for: a) === views[a])

        // Second child: inner split view
        let innerSplit = outer?.arrangedSubviews[1] as? NSSplitView
        #expect(innerSplit != nil)
        #expect(innerSplit?.arrangedSubviews.count == 2)
    }

    // MARK: - Tree Update

    @Test("applying new tree replaces hierarchy")
    func treeUpdate() {
        let container = PaneContainerView()
        let a = PaneID()
        let viewA = testView()

        // Start with single pane
        container.applyTree(.terminal(id: a)) { _ in viewA }
        #expect(container.subviews.first === viewA)

        // Split it
        let b = PaneID()
        let viewB = testView()
        let tree = PaneNode.split(axis: .horizontal, children: [.terminal(id: a), .terminal(id: b)])

        container.applyTree(tree) { paneID in
            paneID == a ? viewA : viewB
        }

        #expect(container.subviews.count == 1)
        #expect(container.subviews.first is NSSplitView)
    }

    // MARK: - Pane Lookup

    @Test("paneView returns correct view for each pane ID")
    func paneViewLookup() {
        let container = PaneContainerView()
        let a = PaneID(), b = PaneID()
        let viewA = testView(), viewB = testView()
        let tree = PaneNode.split(axis: .horizontal, children: [.terminal(id: a), .terminal(id: b)])

        container.applyTree(tree) { paneID in
            paneID == a ? viewA : viewB
        }

        #expect(container.paneView(for: a) === viewA)
        #expect(container.paneView(for: b) === viewB)
        #expect(container.paneView(for: PaneID()) == nil)
    }

    // MARK: - PaneSplitView Constraints

    @Test("split view prevents pane collapse")
    func splitViewPreventsCollapse() {
        let split = PaneSplitView()
        let a = testView(), b = testView()
        split.addArrangedSubview(a)
        split.addArrangedSubview(b)

        // PaneSplitView is its own delegate — canCollapseSubview should return false
        #expect(split.delegate?.splitView?(split, canCollapseSubview: a) == false)
        #expect(split.delegate?.splitView?(split, canCollapseSubview: b) == false)
    }
}
