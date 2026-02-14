// ABOUTME: Observable model tracking which tool windows are assigned to each edge and their visibility.
// ABOUTME: Persists layout state to UserDefaults as JSON; restored on app launch.

import Foundation

@MainActor @Observable
final class ToolWindowLayout {

    /// Which windows are assigned to each edge, in display order.
    var edgeAssignments: [ToolWindowEdge: [ToolWindowID]] = [:]

    /// The currently visible (expanded) window per edge. nil = edge collapsed.
    var visibleWindow: [ToolWindowEdge: ToolWindowID] = [:]

    /// Panel width (left/right) or height (bottom) in points.
    var panelSizes: [ToolWindowEdge: CGFloat] = [:]

    // MARK: - Constants

    private static let minSideWidth: CGFloat = 180
    private static let minBottomHeight: CGFloat = 100
    private static let defaultSideWidth: CGFloat = 280
    private static let defaultBottomHeight: CGFloat = 200
    private static let persistenceKey = "toolWindowLayout"

    // MARK: - Init

    init() {
        restore()
    }

    // MARK: - Queries

    /// Returns the descriptor for a given ID, if registered.
    func descriptor(for id: ToolWindowID) -> ToolWindowDescriptor? {
        ToolWindowDescriptor.all.first { $0.id == id }
    }

    /// Windows assigned to an edge.
    func windows(on edge: ToolWindowEdge) -> [ToolWindowID] {
        edgeAssignments[edge] ?? []
    }

    /// Whether a given edge has any windows assigned.
    func hasWindows(on edge: ToolWindowEdge) -> Bool {
        !(edgeAssignments[edge] ?? []).isEmpty
    }

    /// Whether an edge's panel is currently expanded.
    func isExpanded(_ edge: ToolWindowEdge) -> Bool {
        visibleWindow[edge] != nil
    }

    /// The resolved panel size for an edge, clamped to minimums.
    func panelSize(for edge: ToolWindowEdge) -> CGFloat {
        let raw = panelSizes[edge] ?? (edge.isVertical ? Self.defaultSideWidth : Self.defaultBottomHeight)
        let min = edge.isVertical ? Self.minSideWidth : Self.minBottomHeight
        return max(raw, min)
    }

    // MARK: - Mutations

    /// Toggle a specific tool window: if it's visible, hide it; if another window on the same
    /// edge is visible, switch to this one; if the edge is collapsed, expand with this window.
    func toggleWindow(_ id: ToolWindowID) {
        guard let edge = edge(for: id) else { return }

        if visibleWindow[edge] == id {
            visibleWindow[edge] = nil
        } else {
            visibleWindow[edge] = id
        }
        save()
    }

    /// Collapse or expand an entire edge. When expanding, restores the last visible window
    /// (or the first assigned window as fallback).
    func toggleEdge(_ edge: ToolWindowEdge) {
        if visibleWindow[edge] != nil {
            visibleWindow[edge] = nil
        } else if let first = edgeAssignments[edge]?.first {
            visibleWindow[edge] = first
        }
        save()
    }

    /// Move a window from its current edge to a target edge. Appended at end and made active.
    func moveWindow(_ id: ToolWindowID, to targetEdge: ToolWindowEdge) {
        guard let sourceEdge = edge(for: id), sourceEdge != targetEdge else { return }

        // Remove from source
        edgeAssignments[sourceEdge]?.removeAll { $0 == id }
        if visibleWindow[sourceEdge] == id {
            visibleWindow[sourceEdge] = edgeAssignments[sourceEdge]?.first
        }

        // Add to target
        var targetList = edgeAssignments[targetEdge] ?? []
        targetList.append(id)
        edgeAssignments[targetEdge] = targetList
        visibleWindow[targetEdge] = id

        save()
    }

    /// Reorder a window within its edge.
    func reorderWindow(_ id: ToolWindowID, toIndex index: Int, on edge: ToolWindowEdge) {
        guard var list = edgeAssignments[edge],
              let currentIndex = list.firstIndex(of: id) else { return }
        list.remove(at: currentIndex)
        let clampedIndex = min(max(index, 0), list.count)
        list.insert(id, at: clampedIndex)
        edgeAssignments[edge] = list
        save()
    }

    /// Update panel size for an edge, clamped to minimums.
    func setPanelSize(_ size: CGFloat, for edge: ToolWindowEdge) {
        let min = edge.isVertical ? Self.minSideWidth : Self.minBottomHeight
        panelSizes[edge] = max(size, min)
        save()
    }

    // MARK: - Helpers

    /// Find which edge a window is currently assigned to.
    func edge(for id: ToolWindowID) -> ToolWindowEdge? {
        for (edge, ids) in edgeAssignments where ids.contains(id) {
            return edge
        }
        return nil
    }

    // MARK: - Persistence

    private struct PersistedState: Codable {
        var edgeAssignments: [String: [String]]
        var visibleWindow: [String: String]
        var panelSizes: [String: CGFloat]
    }

    func save() {
        let state = PersistedState(
            edgeAssignments: edgeAssignments.mapKeys(\.rawValue).mapValues { $0.map(\.rawValue) },
            visibleWindow: visibleWindow.compactMapValues { $0 }.mapKeys(\.rawValue).mapValues(\.rawValue),
            panelSizes: panelSizes.mapKeys(\.rawValue)
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.persistenceKey)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            applyDefaults()
            return
        }

        edgeAssignments = Dictionary(uniqueKeysWithValues:
            state.edgeAssignments.compactMap { key, ids -> (ToolWindowEdge, [ToolWindowID])? in
                guard let edge = ToolWindowEdge(rawValue: key) else { return nil }
                return (edge, ids.map { ToolWindowID(rawValue: $0) })
            }
        )
        visibleWindow = Dictionary(uniqueKeysWithValues:
            state.visibleWindow.compactMap { key, val -> (ToolWindowEdge, ToolWindowID)? in
                guard let edge = ToolWindowEdge(rawValue: key) else { return nil }
                return (edge, ToolWindowID(rawValue: val))
            }
        )
        panelSizes = Dictionary(uniqueKeysWithValues:
            state.panelSizes.compactMap { key, val -> (ToolWindowEdge, CGFloat)? in
                guard let edge = ToolWindowEdge(rawValue: key) else { return nil }
                return (edge, val)
            }
        )
    }

    private func applyDefaults() {
        edgeAssignments = [
            .right: [.tasks, .files],
        ]
        visibleWindow = [:]
        panelSizes = [
            .left: Self.defaultSideWidth,
            .right: Self.defaultSideWidth,
            .bottom: Self.defaultBottomHeight,
        ]
    }
}

// MARK: - Dictionary Helpers

private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        Dictionary<T, Value>(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}
