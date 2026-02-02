// ABOUTME: Tests for graph neighbor traversal used by hover/selection highlighting.
// ABOUTME: Validates 1-hop and 2-hop neighbor computation on the dependency graph.

import Testing
@testable import Claide

@Suite("Graph Neighbors")
@MainActor
struct NeighborTests {

    private func makeVM() throws -> GraphViewModel {
        let vm = GraphViewModel()
        vm.setIssues(try BeadsService.decode(Fixtures.beadsJSON))
        return vm
    }

    @Test("Direct neighbors of a connected node returns adjacent nodes")
    func directNeighbors() throws {
        let vm = try makeVM()
        // proj-qwh has dependencies to proj-6q6 and proj-8as
        let neighbors = vm.neighbors(of: "proj-qwh", hops: 1)
        #expect(neighbors.contains("proj-6q6"))
        #expect(neighbors.contains("proj-8as"))
        #expect(!neighbors.contains("proj-qwh")) // doesn't include self
    }

    @Test("Two-hop neighbors includes neighbors of neighbors")
    func twoHopNeighbors() throws {
        let vm = try makeVM()
        // proj-8as connects to proj-qwh (1 hop), which connects to proj-6q6 (2 hops)
        let neighbors = vm.neighbors(of: "proj-8as", hops: 2)
        #expect(neighbors.contains("proj-qwh")) // 1 hop
        #expect(neighbors.contains("proj-6q6")) // 2 hops
    }

    @Test("Disconnected node returns empty set")
    func disconnectedNode() throws {
        let json = """
        [{"id":"solo","title":"Alone","status":"open","priority":0,"issue_type":"task",
          "created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z",
          "dependency_count":0,"dependent_count":0}]
        """.data(using: .utf8)!
        let vm = GraphViewModel()
        vm.setIssues(try BeadsService.decode(json))
        let neighbors = vm.neighbors(of: "solo", hops: 2)
        #expect(neighbors.isEmpty)
    }

    @Test("Zero hops returns empty set")
    func zeroHops() throws {
        let vm = try makeVM()
        let neighbors = vm.neighbors(of: "proj-qwh", hops: 0)
        #expect(neighbors.isEmpty)
    }
}
