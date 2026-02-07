// ABOUTME: Tests for PaneNode binary tree operations.
// ABOUTME: Verifies find, split, close, sibling lookup, and tree traversal.

import Testing
import Foundation
@testable import Claide

@Suite("PaneNode")
struct PaneNodeTests {

    // MARK: - Helpers

    /// Create a leaf node with a given ID (no real view needed for tree tests).
    private func leaf(_ id: UUID = UUID()) -> PaneNode {
        .terminal(id: id)
    }

    // MARK: - Single Node

    @Test("single terminal node lists itself")
    func singleNodeAllPaneIDs() {
        let id = UUID()
        let node = leaf(id)

        #expect(node.allPaneIDs == [id])
    }

    @Test("find returns pane ID in single node")
    func singleNodeFind() {
        let id = UUID()
        let node = leaf(id)

        #expect(node.find(id: id) != nil)
        #expect(node.find(id: UUID()) == nil)
    }

    @Test("contains works for single node")
    func singleNodeContains() {
        let id = UUID()
        let node = leaf(id)

        #expect(node.contains(id: id))
        #expect(!node.contains(id: UUID()))
    }

    // MARK: - Split Tree

    @Test("split tree lists all leaves in order")
    func splitTreeAllPaneIDs() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, first: leaf(a), second: leaf(b))

        #expect(tree.allPaneIDs == [a, b])
    }

    @Test("nested split tree lists leaves depth-first")
    func nestedSplitAllPaneIDs() {
        let a = UUID(), b = UUID(), c = UUID()
        // Tree:  split(horizontal, a, split(vertical, b, c))
        let inner = PaneNode.split(axis: .vertical, first: leaf(b), second: leaf(c))
        let tree = PaneNode.split(axis: .horizontal, first: leaf(a), second: inner)

        #expect(tree.allPaneIDs == [a, b, c])
    }

    @Test("find locates pane in nested tree")
    func nestedFind() {
        let a = UUID(), b = UUID(), c = UUID()
        let inner = PaneNode.split(axis: .vertical, first: leaf(b), second: leaf(c))
        let tree = PaneNode.split(axis: .horizontal, first: leaf(a), second: inner)

        #expect(tree.find(id: a) != nil)
        #expect(tree.find(id: b) != nil)
        #expect(tree.find(id: c) != nil)
        #expect(tree.find(id: UUID()) == nil)
    }

    // MARK: - Splitting

    @Test("splitting a leaf creates a split with the original and new node")
    func splitLeaf() {
        let original = UUID()
        let tree = leaf(original)

        guard let (newTree, newID) = tree.splitting(original, axis: .horizontal) else {
            Issue.record("splitting returned nil")
            return
        }

        // Root should be a split now
        guard case .split(let axis, _, _) = newTree else {
            Issue.record("expected split node")
            return
        }
        #expect(axis == .horizontal)

        // Both original and new should be in the tree
        let ids = newTree.allPaneIDs
        #expect(ids.count == 2)
        #expect(ids.contains(original))
        #expect(ids.contains(newID))
        // Original comes first
        #expect(ids[0] == original)
        #expect(ids[1] == newID)
    }

    @Test("splitting a pane in a nested tree only affects the target")
    func splitNested() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, first: leaf(a), second: leaf(b))

        guard let (newTree, newID) = tree.splitting(b, axis: .vertical) else {
            Issue.record("splitting returned nil")
            return
        }

        let ids = newTree.allPaneIDs
        #expect(ids.count == 3)
        #expect(ids == [a, b, newID])
    }

    @Test("splitting non-existent ID returns nil")
    func splitNonExistent() {
        let tree = leaf()
        #expect(tree.splitting(UUID(), axis: .horizontal) == nil)
    }

    // MARK: - Closing

    @Test("closing the only pane returns nil")
    func closeSolePaneReturnsNil() {
        let id = UUID()
        let tree = leaf(id)

        #expect(tree.closing(id) == nil)
    }

    @Test("closing one side of a split returns the other side")
    func closeOneSideReturnsSibling() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, first: leaf(a), second: leaf(b))

        guard let result = tree.closing(a) else {
            Issue.record("closing returned nil")
            return
        }

        #expect(result.allPaneIDs == [b])
    }

    @Test("closing in a nested tree collapses the parent split")
    func closeNestedCollapses() {
        let a = UUID(), b = UUID(), c = UUID()
        let inner = PaneNode.split(axis: .vertical, first: leaf(b), second: leaf(c))
        let tree = PaneNode.split(axis: .horizontal, first: leaf(a), second: inner)

        // Close b: inner collapses to just c, tree becomes split(a, c)
        guard let result = tree.closing(b) else {
            Issue.record("closing returned nil")
            return
        }

        #expect(result.allPaneIDs == [a, c])
    }

    @Test("closing non-existent ID returns the tree unchanged")
    func closeNonExistentReturnsUnchanged() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, first: leaf(a), second: leaf(b))

        guard let result = tree.closing(UUID()) else {
            Issue.record("closing returned nil unexpectedly")
            return
        }

        #expect(result.allPaneIDs == [a, b])
    }

    // MARK: - Sibling

    @Test("sibling of a pane in a two-pane split is the other pane")
    func siblingInSimpleSplit() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, first: leaf(a), second: leaf(b))

        #expect(tree.siblingPaneID(of: a) == b)
        #expect(tree.siblingPaneID(of: b) == a)
    }

    @Test("sibling of a pane in a nested split returns first leaf of sibling subtree")
    func siblingInNestedSplit() {
        let a = UUID(), b = UUID(), c = UUID()
        let inner = PaneNode.split(axis: .vertical, first: leaf(b), second: leaf(c))
        let tree = PaneNode.split(axis: .horizontal, first: leaf(a), second: inner)

        // Sibling of a is the inner split's first leaf (b)
        #expect(tree.siblingPaneID(of: a) == b)
        // Sibling of b is c (within the inner split)
        #expect(tree.siblingPaneID(of: b) == c)
    }

    @Test("sibling of sole pane returns nil")
    func siblingOfSolePaneIsNil() {
        let id = UUID()
        let tree = leaf(id)

        #expect(tree.siblingPaneID(of: id) == nil)
    }

    // MARK: - Pane Count

    @Test("paneCount returns correct count")
    func paneCount() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(leaf(a).paneCount == 1)

        let two = PaneNode.split(axis: .horizontal, first: leaf(a), second: leaf(b))
        #expect(two.paneCount == 2)

        let inner = PaneNode.split(axis: .vertical, first: leaf(b), second: leaf(c))
        let three = PaneNode.split(axis: .horizontal, first: leaf(a), second: inner)
        #expect(three.paneCount == 3)
    }
}
