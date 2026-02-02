// ABOUTME: Tests that the force-directed graph layout converges and separates nodes.
// ABOUTME: Validates minimum distance between nodes and bounded positioning.

import Testing
import CoreGraphics
@testable import Claide

@Suite("Force Layout")
@MainActor
struct ForceLayoutTests {

    private func makeTestIssues() throws -> [Claide.Issue] {
        try BeadsService.decode(Fixtures.beadsJSON)
    }

    @Test("All nodes receive positions after layout")
    func allNodesPositioned() throws {
        let vm = GraphViewModel()
        vm.setIssues(try makeTestIssues())
        #expect(vm.positions.count == 4)
        for issue in vm.issues {
            #expect(vm.positions[issue.id] != nil)
        }
    }

    @Test("Nodes do not overlap after layout")
    func nodesDoNotOverlap() throws {
        let vm = GraphViewModel()
        vm.setIssues(try makeTestIssues())

        let ids = vm.issues.map(\.id)
        // Minimum center-to-center distance must exceed node diagonal
        // so rendered rectangles (200x80) never overlap
        let nodeWidth = NodeMetrics.graphWidth
        let nodeHeight = NodeMetrics.graphHeight
        let minDistance = sqrt(nodeWidth * nodeWidth + nodeHeight * nodeHeight)

        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let pa = vm.positions[ids[i]]!
                let pb = vm.positions[ids[j]]!
                let dx = pa.x - pb.x
                let dy = pa.y - pb.y
                let dist = sqrt(dx * dx + dy * dy)
                #expect(dist > minDistance, "Nodes \(ids[i]) and \(ids[j]) are too close: \(dist)")
            }
        }
    }

    @Test("Layout converges to finite positions")
    func convergesFinitely() throws {
        let vm = GraphViewModel()
        vm.setIssues(try makeTestIssues())

        let maxCoord: CGFloat = 10000
        for (_, pos) in vm.positions {
            #expect(pos.x.isFinite && abs(pos.x) < maxCoord, "x out of bounds: \(pos.x)")
            #expect(pos.y.isFinite && abs(pos.y) < maxCoord, "y out of bounds: \(pos.y)")
        }
    }

    @Test("Edges are computed from dependencies")
    func edgesFromDependencies() throws {
        let vm = GraphViewModel()
        vm.setIssues(try makeTestIssues())
        #expect(!vm.edges.isEmpty)

        let blocksEdges = vm.edges.filter { $0.type == "blocks" }
        #expect(!blocksEdges.isEmpty)
    }

    @Test("Single node layout doesn't crash")
    func singleNodeLayout() throws {
        let singleJSON = """
        [{"id":"x","title":"Solo","status":"open","priority":0,"issue_type":"task",
          "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z",
          "dependency_count":0,"dependent_count":0}]
        """.data(using: .utf8)!

        let vm = GraphViewModel()
        vm.setIssues(try BeadsService.decode(singleJSON))
        #expect(vm.positions.count == 1)
        #expect(vm.positions["x"] != nil)
    }

    @Test("Empty issue list produces no positions")
    func emptyIssueList() {
        let vm = GraphViewModel()
        vm.setIssues([])
        #expect(vm.positions.isEmpty)
    }
}
