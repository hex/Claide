// ABOUTME: Tests for edge visual property computation (color, dash pattern, arrowheads).
// ABOUTME: Validates mapping from dependency type to visual attributes for graph edges.

import Testing
import SwiftUI
@testable import Claide

@Suite("Edge Visuals")
struct EdgeVisualsTests {

    @Test("Blocks edge is solid red with arrowhead")
    func blocksEdge() {
        let visuals = EdgeVisuals.compute(for: "blocks")
        #expect(visuals.color == Theme.edgeBlocks)
        #expect(!visuals.isDashed)
        #expect(visuals.hasArrowhead)
    }

    @Test("Parent-child edge is dashed gray without arrowhead")
    func parentChildEdge() {
        let visuals = EdgeVisuals.compute(for: "parent-child")
        #expect(visuals.color == Theme.edgeDefault)
        #expect(visuals.isDashed)
        #expect(!visuals.hasArrowhead)
    }

    @Test("Unknown edge type defaults to solid gray with arrowhead")
    func unknownEdge() {
        let visuals = EdgeVisuals.compute(for: "related")
        #expect(visuals.color == Theme.edgeDefault)
        #expect(!visuals.isDashed)
        #expect(visuals.hasArrowhead)
    }
}
