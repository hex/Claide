// ABOUTME: Tests for fixed-size node metrics with hard quality cutoffs.
// ABOUTME: Validates LiteGraph-style rendering: uniform scaling, no morphing.

import Testing
import CoreGraphics
@testable import Claide

@Suite("Node Metrics")
struct NodeMetricsTests {

    @Test("Dimensions scale linearly with zoom")
    func dimensionsScaleLinearly() {
        let full = NodeMetrics.at(zoom: 1.0)
        #expect(full.width == 200)
        #expect(full.height == 80)

        let half = NodeMetrics.at(zoom: 0.5)
        #expect(half.width == 100)
        #expect(half.height == 40)

        let tiny = NodeMetrics.at(zoom: 0.1)
        #expect(tiny.width == 20)
        #expect(tiny.height == 8)
    }

    @Test("Low quality below zoom 0.6")
    func lowQualityThreshold() {
        let below = NodeMetrics.at(zoom: 0.59)
        #expect(below.lowQuality)
        #expect(below.cornerRadius == 0)

        let at = NodeMetrics.at(zoom: 0.6)
        #expect(!at.lowQuality)
        #expect(at.cornerRadius > 0)
    }

    @Test("Title visible at zoom 0.5+, hidden below")
    func titleVisibility() {
        let hidden = NodeMetrics.at(zoom: 0.49)
        #expect(!hidden.showTitle)

        let visible = NodeMetrics.at(zoom: 0.5)
        #expect(visible.showTitle)
    }

    @Test("ID visible at zoom 0.6+")
    func idTextVisibility() {
        let mid = NodeMetrics.at(zoom: 0.55)
        #expect(mid.showTitle)
        #expect(!mid.showIdText)

        let full = NodeMetrics.at(zoom: 0.6)
        #expect(full.showIdText)
    }

    @Test("Badges visible at zoom 0.65+")
    func badgesVisibility() {
        let below = NodeMetrics.at(zoom: 0.64)
        #expect(!below.showBadges)

        let at = NodeMetrics.at(zoom: 0.65)
        #expect(at.showBadges)
    }

    @Test("Info row visible at zoom 0.7+")
    func infoRowVisibility() {
        let below = NodeMetrics.at(zoom: 0.69)
        #expect(!below.showInfoRow)

        let at = NodeMetrics.at(zoom: 0.7)
        #expect(at.showInfoRow)
    }

    @Test("Corner radius scales with zoom at full quality")
    func cornerRadiusScaling() {
        let m = NodeMetrics.at(zoom: 1.0)
        #expect(m.cornerRadius == 4)

        let m2 = NodeMetrics.at(zoom: 0.8)
        #expect(abs(m2.cornerRadius - 3.2) < 0.001)
    }

    @Test("High zoom maintains full quality")
    func highZoomFullQuality() {
        let m = NodeMetrics.at(zoom: 3.0)
        #expect(m.width == 600)
        #expect(m.height == 240)
        #expect(!m.lowQuality)
        #expect(m.showTitle)
        #expect(m.showIdText)
        #expect(m.showBadges)
        #expect(m.showInfoRow)
    }
}

@Suite("Priority Colors")
struct PriorityColorTests {

    private func issueWithPriority(_ priority: Int) throws -> Claide.Issue {
        let json = """
        [{"id":"t","title":"T","status":"open","priority":\(priority),
          "issue_type":"task","created_at":"2026-01-01T00:00:00Z",
          "updated_at":"2026-01-01T00:00:00Z",
          "dependency_count":0,"dependent_count":0}]
        """.data(using: .utf8)!
        return try BeadsService.decode(json)[0]
    }

    @Test("P0 maps to critical color")
    func p0Critical() throws {
        let issue = try issueWithPriority(0)
        #expect(issue.priorityColor == Theme.priorityCritical)
    }

    @Test("P1 maps to high color")
    func p1High() throws {
        let issue = try issueWithPriority(1)
        #expect(issue.priorityColor == Theme.priorityHigh)
    }

    @Test("P2 maps to medium color")
    func p2Medium() throws {
        let issue = try issueWithPriority(2)
        #expect(issue.priorityColor == Theme.priorityMedium)
    }

    @Test("P3 maps to low color")
    func p3Low() throws {
        let issue = try issueWithPriority(3)
        #expect(issue.priorityColor == Theme.priorityLow)
    }

    @Test("P4 maps to backlog color")
    func p4Backlog() throws {
        let issue = try issueWithPriority(4)
        #expect(issue.priorityColor == Theme.priorityBacklog)
    }

    @Test("Unknown priority falls back to muted")
    func unknownPriority() throws {
        let issue = try issueWithPriority(99)
        #expect(issue.priorityColor == Theme.textMuted)
    }
}
