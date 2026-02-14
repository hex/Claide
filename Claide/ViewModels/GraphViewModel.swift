// ABOUTME: Manages issue data and force-directed graph layout positioning.
// ABOUTME: Computes node positions via repulsion/attraction simulation.

import SwiftUI

enum DataSource: String, CaseIterable {
    case beads = "Beads"
    case claudeCode = "Claude Code Tasks"
}

@MainActor @Observable
final class GraphViewModel {
    var issues: [Issue] = []
    var positions: [String: CGPoint] = [:]
    var error: String?
    var isLoading: Bool = false
    var layoutGeneration: Int = 0
    var dataSource: DataSource = .beads

    /// Number of issues that are not yet closed
    var uncompletedCount: Int {
        issues.count { $0.status != "closed" }
    }

    // Force layout constants
    private let repulsion: CGFloat = 8000
    private let attraction: CGFloat = 0.02
    private let damping: CGFloat = 0.85
    private let idealLength: CGFloat = NodeMetrics.graphWidth * 1.5
    private let iterations: Int = 200

    /// Edges derived from all issue dependencies
    var edges: [(from: String, to: String, type: String)] {
        issues.flatMap { issue in
            (issue.dependencies ?? []).map { dep in
                (from: dep.issueID, to: dep.dependsOnID, type: dep.type)
            }
        }
    }

    /// Unique edges (deduplicated by source/target pair)
    var uniqueEdges: [(from: String, to: String, type: String)] {
        var seen = Set<String>()
        return edges.filter { edge in
            let key = [edge.from, edge.to].sorted().joined(separator: "-")
            return seen.insert(key).inserted
        }
    }

    func loadIssues(workingDirectory: String? = nil) async {
        error = nil
        do {
            switch dataSource {
            case .beads:
                issues = try await BeadsService.loadIssues(workingDirectory: workingDirectory)
            case .claudeCode:
                issues = try ClaudeTaskService.loadIssues()
            }
            computeLayout()
        } catch {
            issues = []
            switch error {
            case BeadsError.noDatabase, BeadsError.binaryNotFound:
                break
            default:
                self.error = error.localizedDescription
            }
        }
    }

    /// Set issues directly (for testing or preview)
    func setIssues(_ newIssues: [Issue]) {
        issues = newIssues
        computeLayout()
    }

    /// Run force-directed layout simulation
    func computeLayout() {
        guard !issues.isEmpty else { return }

        let issueIDs = issues.map(\.id)
        let idSet = Set(issueIDs)

        // Initialize positions in a circle
        let center = CGPoint(x: 400, y: 300)
        let radius: CGFloat = CGFloat(issues.count) * 40
        for (i, id) in issueIDs.enumerated() {
            let angle = (CGFloat(i) / CGFloat(issues.count)) * 2 * .pi
            positions[id] = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }

        // Build edge list (only edges where both endpoints exist)
        let validEdges = edges.filter { idSet.contains($0.from) && idSet.contains($0.to) }

        // Simulate
        var velocities = [String: CGPoint]()
        for id in issueIDs { velocities[id] = .zero }

        for _ in 0..<iterations {
            var forces = [String: CGPoint]()
            for id in issueIDs { forces[id] = .zero }

            // Repulsion between all pairs
            for i in 0..<issueIDs.count {
                for j in (i + 1)..<issueIDs.count {
                    let a = issueIDs[i]
                    let b = issueIDs[j]
                    guard let pa = positions[a], let pb = positions[b] else { continue }
                    let dx = pa.x - pb.x
                    let dy = pa.y - pb.y
                    let dist = max(sqrt(dx * dx + dy * dy), 1)
                    let force = repulsion / (dist * dist)
                    let fx = (dx / dist) * force
                    let fy = (dy / dist) * force
                    forces[a] = CGPoint(x: (forces[a]?.x ?? 0) + fx, y: (forces[a]?.y ?? 0) + fy)
                    forces[b] = CGPoint(x: (forces[b]?.x ?? 0) - fx, y: (forces[b]?.y ?? 0) - fy)
                }
            }

            // Attraction along edges
            for edge in validEdges {
                guard let pa = positions[edge.from], let pb = positions[edge.to] else { continue }
                let dx = pb.x - pa.x
                let dy = pb.y - pa.y
                let dist = sqrt(dx * dx + dy * dy)
                let delta = dist - idealLength
                let force = attraction * delta
                let fx = (dx / max(dist, 1)) * force
                let fy = (dy / max(dist, 1)) * force
                forces[edge.from] = CGPoint(
                    x: (forces[edge.from]?.x ?? 0) + fx,
                    y: (forces[edge.from]?.y ?? 0) + fy
                )
                forces[edge.to] = CGPoint(
                    x: (forces[edge.to]?.x ?? 0) - fx,
                    y: (forces[edge.to]?.y ?? 0) - fy
                )
            }

            // Apply forces with damping
            for id in issueIDs {
                let vx = ((velocities[id]?.x ?? 0) + (forces[id]?.x ?? 0)) * damping
                let vy = ((velocities[id]?.y ?? 0) + (forces[id]?.y ?? 0)) * damping
                velocities[id] = CGPoint(x: vx, y: vy)
                positions[id] = CGPoint(
                    x: (positions[id]?.x ?? 0) + vx,
                    y: (positions[id]?.y ?? 0) + vy
                )
            }
        }

        layoutGeneration += 1
    }

    /// Compute all node IDs reachable within the given number of hops from a starting node.
    /// Excludes the starting node itself.
    func neighbors(of nodeID: String, hops: Int) -> Set<String> {
        guard hops > 0 else { return [] }
        var result = Set<String>()
        var frontier: Set<String> = [nodeID]
        for _ in 0..<hops {
            var next = Set<String>()
            for id in frontier {
                for edge in edges {
                    if edge.from == id { next.insert(edge.to) }
                    if edge.to == id { next.insert(edge.from) }
                }
            }
            next.subtract(result)
            next.remove(nodeID)
            result.formUnion(next)
            frontier = next
        }
        return result
    }
}
