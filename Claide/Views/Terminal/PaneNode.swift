// ABOUTME: N-ary tree representing a split-pane layout within a single tab.
// ABOUTME: Leaves hold pane IDs; branches define split orientation with N children.

import Foundation

/// Orientation of a split divider.
enum SplitAxis: Equatable {
    case horizontal  // panes side-by-side (left | right), divider is vertical
    case vertical    // panes stacked (top / bottom), divider is horizontal
}

/// Pane identifier within a tab's split layout.
typealias PaneID = UUID

/// N-ary tree node for a split-pane terminal layout.
/// Leaves are terminal panes; internal nodes are splits with N >= 2 children.
/// Same-axis splits add siblings (equal distribution); cross-axis splits nest.
indirect enum PaneNode {
    case terminal(id: PaneID)
    case split(axis: SplitAxis, children: [PaneNode])

    // MARK: - Queries

    /// All terminal pane IDs in depth-first order.
    var allPaneIDs: [PaneID] {
        switch self {
        case .terminal(let id):
            return [id]
        case .split(_, let children):
            return children.flatMap { $0.allPaneIDs }
        }
    }

    /// Number of terminal panes in this subtree.
    var paneCount: Int {
        switch self {
        case .terminal:
            return 1
        case .split(_, let children):
            return children.reduce(0) { $0 + $1.paneCount }
        }
    }

    /// Whether this subtree contains a pane with the given ID.
    func contains(id: PaneID) -> Bool {
        find(id: id) != nil
    }

    /// Find the terminal node with the given ID, returning its ID if found.
    func find(id: PaneID) -> PaneID? {
        switch self {
        case .terminal(let paneID):
            return paneID == id ? paneID : nil
        case .split(_, let children):
            return children.lazy.compactMap { $0.find(id: id) }.first
        }
    }

    /// Find the first leaf ID of an adjacent sibling for the given pane.
    /// Returns nil if the pane is the root (no sibling).
    func siblingPaneID(of targetID: PaneID) -> PaneID? {
        switch self {
        case .terminal:
            return nil
        case .split(_, let children):
            guard let index = children.firstIndex(where: { $0.contains(id: targetID) }) else {
                return nil
            }

            let child = children[index]

            // Target is a direct child terminal — return adjacent child's first leaf
            if case .terminal(let id) = child, id == targetID {
                let siblingIndex = index + 1 < children.count ? index + 1 : index - 1
                guard siblingIndex >= 0 else { return nil }
                return children[siblingIndex].allPaneIDs.first
            }

            // Target is deeper — try resolving within the child subtree first
            if let innerSibling = child.siblingPaneID(of: targetID) {
                return innerSibling
            }
            // Fall back to adjacent child's first leaf
            let siblingIndex = index + 1 < children.count ? index + 1 : index - 1
            guard siblingIndex >= 0 else { return nil }
            return children[siblingIndex].allPaneIDs.first
        }
    }

    // MARK: - Mutations (return new tree)

    /// Split the pane with the given ID, creating a new sibling.
    /// Same-axis splits add a sibling to the parent; cross-axis splits nest.
    /// Returns the updated tree and the new pane's ID, or nil if the target was not found.
    func splitting(_ targetID: PaneID, axis: SplitAxis) -> (tree: PaneNode, newID: PaneID)? {
        switch self {
        case .terminal(let id) where id == targetID:
            let newID = PaneID()
            let splitNode = PaneNode.split(
                axis: axis,
                children: [self, .terminal(id: newID)]
            )
            return (splitNode, newID)

        case .terminal:
            return nil

        case .split(let ax, let children):
            guard let index = children.firstIndex(where: { $0.contains(id: targetID) }) else {
                return nil
            }

            // Direct child terminal with same axis → add sibling to this split
            if case .terminal(let id) = children[index], id == targetID, ax == axis {
                let newID = PaneID()
                var newChildren = children
                newChildren.insert(.terminal(id: newID), at: index + 1)
                return (.split(axis: ax, children: newChildren), newID)
            }

            // Different axis or deeper target → recurse into the child
            guard let result = children[index].splitting(targetID, axis: axis) else {
                return nil
            }
            var newChildren = children
            newChildren[index] = result.tree
            return (.split(axis: ax, children: newChildren), result.newID)
        }
    }

    /// Close the pane with the given ID. Returns the pruned tree,
    /// or nil if this was the last pane (caller should close the tab).
    func closing(_ targetID: PaneID) -> PaneNode? {
        switch self {
        case .terminal(let id):
            return id == targetID ? nil : self

        case .split(let ax, let children):
            guard let index = children.firstIndex(where: { $0.contains(id: targetID) }) else {
                return self
            }

            // Direct child terminal — remove from children
            if case .terminal(let id) = children[index], id == targetID {
                var newChildren = children
                newChildren.remove(at: index)
                return newChildren.count == 1 ? newChildren[0] : .split(axis: ax, children: newChildren)
            }

            // Recurse into subtree
            if let newChild = children[index].closing(targetID) {
                var newChildren = children
                newChildren[index] = newChild
                return .split(axis: ax, children: newChildren)
            } else {
                // Child subtree fully collapsed
                var newChildren = children
                newChildren.remove(at: index)
                return newChildren.count == 1 ? newChildren[0] : .split(axis: ax, children: newChildren)
            }
        }
    }
}
