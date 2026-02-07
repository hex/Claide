// ABOUTME: Binary tree representing a split-pane layout within a single tab.
// ABOUTME: Leaves hold pane IDs; branches define split orientation.

import Foundation

/// Orientation of a split divider.
enum SplitAxis: Equatable {
    case horizontal  // panes side-by-side (left | right), divider is vertical
    case vertical    // panes stacked (top / bottom), divider is horizontal
}

/// Pane identifier within a tab's split layout.
typealias PaneID = UUID

/// Binary tree node for a split-pane terminal layout.
/// Leaves are terminal panes; internal nodes are splits.
indirect enum PaneNode {
    case terminal(id: PaneID)
    case split(axis: SplitAxis, first: PaneNode, second: PaneNode)

    // MARK: - Queries

    /// All terminal pane IDs in depth-first order.
    var allPaneIDs: [PaneID] {
        switch self {
        case .terminal(let id):
            return [id]
        case .split(_, let first, let second):
            return first.allPaneIDs + second.allPaneIDs
        }
    }

    /// Number of terminal panes in this subtree.
    var paneCount: Int {
        switch self {
        case .terminal:
            return 1
        case .split(_, let first, let second):
            return first.paneCount + second.paneCount
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
        case .split(_, let first, let second):
            return first.find(id: id) ?? second.find(id: id)
        }
    }

    /// Find the first leaf ID of the sibling subtree for the given pane.
    /// Returns nil if the pane is the root (no sibling).
    func siblingPaneID(of targetID: PaneID) -> PaneID? {
        switch self {
        case .terminal:
            return nil
        case .split(_, let first, let second):
            // Direct children: return the other side's first leaf
            if first.contains(id: targetID) && second.contains(id: targetID) {
                // Target is deeper — can't determine sibling at this level
                return nil
            }
            if case .terminal(let id) = first, id == targetID {
                return second.allPaneIDs.first
            }
            if case .terminal(let id) = second, id == targetID {
                return first.allPaneIDs.first
            }
            // Target is in one of the subtrees
            if first.contains(id: targetID) {
                // Check if the first subtree can resolve it internally
                if let innerSibling = first.siblingPaneID(of: targetID) {
                    return innerSibling
                }
                // Otherwise the sibling is the second subtree's first leaf
                return second.allPaneIDs.first
            }
            if second.contains(id: targetID) {
                if let innerSibling = second.siblingPaneID(of: targetID) {
                    return innerSibling
                }
                return first.allPaneIDs.first
            }
            return nil
        }
    }

    // MARK: - Mutations (return new tree)

    /// Split the pane with the given ID, creating a new sibling.
    /// Returns the updated tree and the new pane's ID, or nil if the target was not found.
    func splitting(_ targetID: PaneID, axis: SplitAxis) -> (tree: PaneNode, newID: PaneID)? {
        switch self {
        case .terminal(let id) where id == targetID:
            let newID = PaneID()
            let splitNode = PaneNode.split(
                axis: axis,
                first: self,
                second: .terminal(id: newID)
            )
            return (splitNode, newID)

        case .terminal:
            return nil

        case .split(let ax, let first, let second):
            if let result = first.splitting(targetID, axis: axis) {
                return (.split(axis: ax, first: result.tree, second: second), result.newID)
            }
            if let result = second.splitting(targetID, axis: axis) {
                return (.split(axis: ax, first: first, second: result.tree), result.newID)
            }
            return nil
        }
    }

    /// Close the pane with the given ID. Returns the pruned tree,
    /// or nil if this was the last pane (caller should close the tab).
    func closing(_ targetID: PaneID) -> PaneNode? {
        switch self {
        case .terminal(let id):
            return id == targetID ? nil : self

        case .split(_, let first, let second):
            // Direct child is the target: return the sibling
            if case .terminal(let id) = first, id == targetID {
                return second
            }
            if case .terminal(let id) = second, id == targetID {
                return first
            }
            // Recurse into whichever subtree contains the target
            if first.contains(id: targetID) {
                guard let newFirst = first.closing(targetID) else {
                    return second
                }
                return .split(axis: axis, first: newFirst, second: second)
            }
            if second.contains(id: targetID) {
                guard let newSecond = second.closing(targetID) else {
                    return first
                }
                return .split(axis: axis, first: first, second: newSecond)
            }
            return self
        }
    }

    /// The axis of this node (only valid for split nodes).
    private var axis: SplitAxis {
        guard case .split(let ax, _, _) = self else {
            fatalError("axis called on terminal node")
        }
        return ax
    }
}
