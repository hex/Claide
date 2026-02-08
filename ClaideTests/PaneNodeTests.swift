// ABOUTME: Tests for PaneNode n-ary tree operations.
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
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b)])

        #expect(tree.allPaneIDs == [a, b])
    }

    @Test("nested split tree lists leaves depth-first")
    func nestedSplitAllPaneIDs() {
        let a = UUID(), b = UUID(), c = UUID()
        let inner = PaneNode.split(axis: .vertical, children: [leaf(b), leaf(c)])
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), inner])

        #expect(tree.allPaneIDs == [a, b, c])
    }

    @Test("n-ary split lists all children in order")
    func nArySplitAllPaneIDs() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b), leaf(c), leaf(d)])

        #expect(tree.allPaneIDs == [a, b, c, d])
    }

    @Test("find locates pane in nested tree")
    func nestedFind() {
        let a = UUID(), b = UUID(), c = UUID()
        let inner = PaneNode.split(axis: .vertical, children: [leaf(b), leaf(c)])
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), inner])

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
        guard case .split(let axis, let children) = newTree else {
            Issue.record("expected split node")
            return
        }
        #expect(axis == .horizontal)
        #expect(children.count == 2)

        // Both original and new should be in the tree
        let ids = newTree.allPaneIDs
        #expect(ids.count == 2)
        #expect(ids[0] == original)
        #expect(ids[1] == newID)
    }

    @Test("same-axis split adds sibling to existing split")
    func sameAxisSplitAddsSibling() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b)])

        guard let (newTree, newID) = tree.splitting(a, axis: .horizontal) else {
            Issue.record("splitting returned nil")
            return
        }

        // Should still be a single-level split with 3 children
        guard case .split(let axis, let children) = newTree else {
            Issue.record("expected split node")
            return
        }
        #expect(axis == .horizontal)
        #expect(children.count == 3)

        let ids = newTree.allPaneIDs
        #expect(ids == [a, newID, b])
    }

    @Test("repeated same-axis splits produce flat n-ary tree")
    func repeatedSameAxisSplitsProduceFlatTree() {
        let a = UUID()
        var tree = PaneNode.terminal(id: a)
        var allIDs = [a]

        // Split 4 more times along the same axis
        for _ in 0..<4 {
            guard let (newTree, newID) = tree.splitting(allIDs.last!, axis: .horizontal) else {
                Issue.record("splitting returned nil")
                return
            }
            tree = newTree
            allIDs.append(newID)
        }

        // Should be split(horizontal, [a, b, c, d, e]) — flat, not nested
        guard case .split(let axis, let children) = tree else {
            Issue.record("expected split node")
            return
        }
        #expect(axis == .horizontal)
        #expect(children.count == 5)
        #expect(tree.allPaneIDs == allIDs)
    }

    @Test("different-axis split nests within parent split")
    func differentAxisSplitNests() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b)])

        guard let (newTree, newID) = tree.splitting(b, axis: .vertical) else {
            Issue.record("splitting returned nil")
            return
        }

        // Root should still be horizontal with 2 children
        guard case .split(let axis, let children) = newTree else {
            Issue.record("expected split node")
            return
        }
        #expect(axis == .horizontal)
        #expect(children.count == 2)

        // Second child should now be a vertical split containing b and newID
        guard case .split(let innerAxis, let innerChildren) = children[1] else {
            Issue.record("expected nested split")
            return
        }
        #expect(innerAxis == .vertical)
        #expect(innerChildren.count == 2)
        #expect(newTree.allPaneIDs == [a, b, newID])
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

    @Test("closing one side of a two-child split unwraps to the remaining child")
    func closeOneSideReturnsSibling() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b)])

        guard let result = tree.closing(a) else {
            Issue.record("closing returned nil")
            return
        }

        #expect(result.allPaneIDs == [b])
        // Should unwrap to a terminal, not a split with 1 child
        if case .terminal = result {} else {
            Issue.record("expected terminal node after closing to 1 child")
        }
    }

    @Test("closing one child from a three-child split leaves two-child split")
    func closeFromThreeChildSplit() {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b), leaf(c)])

        guard let result = tree.closing(b) else {
            Issue.record("closing returned nil")
            return
        }

        #expect(result.allPaneIDs == [a, c])
        guard case .split(_, let children) = result else {
            Issue.record("expected split node")
            return
        }
        #expect(children.count == 2)
    }

    @Test("closing in a nested tree collapses the parent split")
    func closeNestedCollapses() {
        let a = UUID(), b = UUID(), c = UUID()
        let inner = PaneNode.split(axis: .vertical, children: [leaf(b), leaf(c)])
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), inner])

        // Close b: inner collapses to just c, tree becomes split(horizontal, [a, c])
        guard let result = tree.closing(b) else {
            Issue.record("closing returned nil")
            return
        }

        #expect(result.allPaneIDs == [a, c])
    }

    @Test("closing non-existent ID returns the tree unchanged")
    func closeNonExistentReturnsUnchanged() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b)])

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
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b)])

        #expect(tree.siblingPaneID(of: a) == b)
        #expect(tree.siblingPaneID(of: b) == a)
    }

    @Test("sibling in n-ary split returns adjacent child")
    func siblingInNArySplit() {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b), leaf(c)])

        // Next sibling of a is b
        #expect(tree.siblingPaneID(of: a) == b)
        // Next sibling of b is c
        #expect(tree.siblingPaneID(of: b) == c)
        // c is last — sibling is previous (b)
        #expect(tree.siblingPaneID(of: c) == b)
    }

    @Test("sibling of a pane in a nested split returns first leaf of sibling subtree")
    func siblingInNestedSplit() {
        let a = UUID(), b = UUID(), c = UUID()
        let inner = PaneNode.split(axis: .vertical, children: [leaf(b), leaf(c)])
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), inner])

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

    // MARK: - Adjacent Pane (Directional Navigation)

    @Test("adjacent pane in simple horizontal split")
    func adjacentInHorizontalSplit() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b)])

        #expect(tree.adjacentPaneID(of: a, direction: .right) == b)
        #expect(tree.adjacentPaneID(of: b, direction: .left) == a)
        // No vertical neighbors in a horizontal-only split
        #expect(tree.adjacentPaneID(of: a, direction: .up) == nil)
        #expect(tree.adjacentPaneID(of: a, direction: .down) == nil)
    }

    @Test("adjacent pane in simple vertical split")
    func adjacentInVerticalSplit() {
        let a = UUID(), b = UUID()
        let tree = PaneNode.split(axis: .vertical, children: [leaf(a), leaf(b)])

        #expect(tree.adjacentPaneID(of: a, direction: .down) == b)
        #expect(tree.adjacentPaneID(of: b, direction: .up) == a)
        // No horizontal neighbors in a vertical-only split
        #expect(tree.adjacentPaneID(of: a, direction: .left) == nil)
        #expect(tree.adjacentPaneID(of: a, direction: .right) == nil)
    }

    @Test("adjacent pane in nested split crosses axis boundary")
    func adjacentInNestedSplit() {
        // Layout: [A | [B / C]]
        // A is left, B is top-right, C is bottom-right
        let a = UUID(), b = UUID(), c = UUID()
        let inner = PaneNode.split(axis: .vertical, children: [leaf(b), leaf(c)])
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), inner])

        // Horizontal movement from B goes to A
        #expect(tree.adjacentPaneID(of: b, direction: .left) == a)
        #expect(tree.adjacentPaneID(of: c, direction: .left) == a)
        // Horizontal movement from A goes into the inner split's first leaf
        #expect(tree.adjacentPaneID(of: a, direction: .right) == b)
        // Vertical movement within inner split
        #expect(tree.adjacentPaneID(of: b, direction: .down) == c)
        #expect(tree.adjacentPaneID(of: c, direction: .up) == b)
        // No vertical movement for A (it's alone on vertical axis)
        #expect(tree.adjacentPaneID(of: a, direction: .up) == nil)
        #expect(tree.adjacentPaneID(of: a, direction: .down) == nil)
    }

    @Test("adjacent pane in n-ary split navigates through all siblings")
    func adjacentInNArySplit() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let tree = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b), leaf(c), leaf(d)])

        #expect(tree.adjacentPaneID(of: a, direction: .right) == b)
        #expect(tree.adjacentPaneID(of: b, direction: .right) == c)
        #expect(tree.adjacentPaneID(of: c, direction: .right) == d)
        #expect(tree.adjacentPaneID(of: d, direction: .right) == nil) // boundary
        #expect(tree.adjacentPaneID(of: d, direction: .left) == c)
        #expect(tree.adjacentPaneID(of: a, direction: .left) == nil) // boundary
    }

    @Test("adjacent pane returns nil for single terminal")
    func adjacentInSingleTerminal() {
        let id = UUID()
        let tree = leaf(id)

        #expect(tree.adjacentPaneID(of: id, direction: .left) == nil)
        #expect(tree.adjacentPaneID(of: id, direction: .right) == nil)
        #expect(tree.adjacentPaneID(of: id, direction: .up) == nil)
        #expect(tree.adjacentPaneID(of: id, direction: .down) == nil)
    }

    @Test("adjacent picks nearest leaf when crossing into subtree")
    func adjacentPicksNearestLeaf() {
        // Layout: [[A / B] | C]
        // Going left from C should reach B (last leaf of left subtree), not A
        let a = UUID(), b = UUID(), c = UUID()
        let inner = PaneNode.split(axis: .vertical, children: [leaf(a), leaf(b)])
        let tree = PaneNode.split(axis: .horizontal, children: [inner, leaf(c)])

        #expect(tree.adjacentPaneID(of: c, direction: .left) == b)
        // Going right from A enters C (first/only leaf of right subtree)
        #expect(tree.adjacentPaneID(of: a, direction: .right) == c)
    }

    // MARK: - Pane Count

    @Test("paneCount returns correct count")
    func paneCount() {
        let a = UUID(), b = UUID(), c = UUID()
        #expect(leaf(a).paneCount == 1)

        let two = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b)])
        #expect(two.paneCount == 2)

        let inner = PaneNode.split(axis: .vertical, children: [leaf(b), leaf(c)])
        let three = PaneNode.split(axis: .horizontal, children: [leaf(a), inner])
        #expect(three.paneCount == 3)

        let four = PaneNode.split(axis: .horizontal, children: [leaf(a), leaf(b), leaf(c), leaf(UUID())])
        #expect(four.paneCount == 4)
    }
}
