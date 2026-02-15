// ABOUTME: Parses tmux layout descriptor strings into a tree of pane nodes.
// ABOUTME: Handles horizontal/vertical splits, nesting, and checksum stripping.

import Foundation

/// A node in a tmux layout tree.
///
/// Layout descriptors encode the pane arrangement of a tmux window as a
/// compact string. Each node has dimensions and position; leaf nodes have
/// a pane ID, container nodes have children in a split direction.
enum TmuxLayoutNode: Equatable {
    case leaf(width: Int, height: Int, x: Int, y: Int, paneID: Int)
    case horizontal(width: Int, height: Int, x: Int, y: Int, children: [TmuxLayoutNode])
    case vertical(width: Int, height: Int, x: Int, y: Int, children: [TmuxLayoutNode])

    /// The split axis of the container that directly holds the given pane.
    /// Returns nil if the pane is not found or is the root leaf.
    func parentAxis(of paneID: Int) -> SplitAxis? {
        switch self {
        case .leaf:
            return nil
        case .horizontal(_, _, _, _, let children):
            for child in children {
                if case .leaf(_, _, _, _, let id) = child, id == paneID {
                    return .horizontal
                }
                if let found = child.parentAxis(of: paneID) {
                    return found
                }
            }
            return nil
        case .vertical(_, _, _, _, let children):
            for child in children {
                if case .leaf(_, _, _, _, let id) = child, id == paneID {
                    return .vertical
                }
                if let found = child.parentAxis(of: paneID) {
                    return found
                }
            }
            return nil
        }
    }

    /// All pane IDs in this subtree.
    var allPaneIDs: [Int] {
        switch self {
        case .leaf(_, _, _, _, let paneID):
            return [paneID]
        case .horizontal(_, _, _, _, let children), .vertical(_, _, _, _, let children):
            return children.flatMap { $0.allPaneIDs }
        }
    }
}

/// Recursive descent parser for tmux layout descriptor strings.
///
/// Format: `[checksum,]WxH,X,Y[,paneID | {children} | [children]]`
/// `{` = horizontal split (left-right), `[` = vertical split (top-bottom).
enum TmuxLayoutParser {

    /// Parse a tmux layout descriptor into a layout node tree.
    ///
    /// Returns nil if the string is malformed.
    static func parse(_ descriptor: String) -> TmuxLayoutNode? {
        let stripped = stripChecksum(descriptor)
        guard !stripped.isEmpty else { return nil }
        var index = stripped.startIndex
        return parseNode(stripped, &index)
    }

    // MARK: - Private

    /// Strip the leading 4-hex-digit checksum and comma if present.
    private static func stripChecksum(_ s: String) -> String {
        // Checksum format: exactly 4 hex chars followed by comma
        guard s.count > 5 else { return s }
        let prefix = s.prefix(4)
        let allHex = prefix.allSatisfy { $0.isHexDigit }
        if allHex && s[s.index(s.startIndex, offsetBy: 4)] == "," {
            return String(s.dropFirst(5))
        }
        return s
    }

    /// Parse a single node starting at `index`.
    ///
    /// A node is: `WxH,X,Y` followed by one of:
    /// - `,paneID` (leaf)
    /// - `{children}` (horizontal split)
    /// - `[children]` (vertical split)
    /// - nothing (treated as leaf with paneID -1, shouldn't happen in practice)
    private static func parseNode(_ s: String, _ index: inout String.Index) -> TmuxLayoutNode? {
        // Parse WxH
        guard let width = parseInt(s, &index) else { return nil }
        guard consume(s, &index, "x") else { return nil }
        guard let height = parseInt(s, &index) else { return nil }

        // Parse ,X,Y
        guard consume(s, &index, ",") else { return nil }
        guard let x = parseInt(s, &index) else { return nil }
        guard consume(s, &index, ",") else { return nil }
        guard let y = parseInt(s, &index) else { return nil }

        // What follows?
        if index < s.endIndex {
            let next = s[index]

            if next == "{" {
                // Horizontal split
                index = s.index(after: index) // skip {
                var children: [TmuxLayoutNode] = []
                while index < s.endIndex && s[index] != "}" {
                    if !children.isEmpty {
                        guard consume(s, &index, ",") else { return nil }
                    }
                    guard let child = parseNode(s, &index) else { return nil }
                    children.append(child)
                }
                guard consume(s, &index, "}") else { return nil }
                return .horizontal(width: width, height: height, x: x, y: y, children: children)
            }

            if next == "[" {
                // Vertical split
                index = s.index(after: index) // skip [
                var children: [TmuxLayoutNode] = []
                while index < s.endIndex && s[index] != "]" {
                    if !children.isEmpty {
                        guard consume(s, &index, ",") else { return nil }
                    }
                    guard let child = parseNode(s, &index) else { return nil }
                    children.append(child)
                }
                guard consume(s, &index, "]") else { return nil }
                return .vertical(width: width, height: height, x: x, y: y, children: children)
            }

            if next == "," {
                // Leaf with pane ID
                index = s.index(after: index) // skip ,
                guard let paneID = parseInt(s, &index) else { return nil }
                return .leaf(width: width, height: height, x: x, y: y, paneID: paneID)
            }
        }

        // End of string with just WxH,X,Y — shouldn't happen in valid tmux output
        return nil
    }

    /// Parse an integer from the current position, advancing `index`.
    private static func parseInt(_ s: String, _ index: inout String.Index) -> Int? {
        let start = index
        while index < s.endIndex && s[index].isNumber {
            index = s.index(after: index)
        }
        guard start != index else { return nil }
        return Int(s[start..<index])
    }

    /// Consume a specific character at `index`, advancing past it.
    @discardableResult
    private static func consume(_ s: String, _ index: inout String.Index, _ char: Character) -> Bool {
        guard index < s.endIndex && s[index] == char else { return false }
        index = s.index(after: index)
        return true
    }
}
