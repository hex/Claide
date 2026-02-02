// ABOUTME: Tests for node visual property computation (size, border, age, badges, deps).
// ABOUTME: Validates mapping from issue data to visual attributes used by Canvas rendering.

import Testing
import SwiftUI
@testable import Claide

@Suite("Node Visuals")
struct NodeVisualsTests {

    // MARK: - Test Helpers

    private func makeIssue(
        id: String = "t-1",
        title: String = "Test",
        status: String = "open",
        priority: Int = 2,
        issueType: String = "task",
        createdAt: String = "2026-02-01T00:00:00Z",
        dependentCount: Int = 0,
        dependencyCount: Int = 0,
        dependencies: [(issueID: String, dependsOnID: String, type: String)]? = nil
    ) throws -> Claide.Issue {
        var depJSON = "null"
        if let deps = dependencies {
            let entries = deps.map { dep in
                """
                {"issue_id":"\(dep.issueID)","depends_on_id":"\(dep.dependsOnID)","type":"\(dep.type)","created_at":"2026-01-01T00:00:00Z","created_by":"test"}
                """
            }
            depJSON = "[\(entries.joined(separator: ","))]"
        }
        let json = """
        [{"id":"\(id)","title":"\(title)","status":"\(status)","priority":\(priority),
          "issue_type":"\(issueType)","created_at":"\(createdAt)",
          "updated_at":"2026-02-01T00:00:00Z",
          "dependencies":\(depJSON),
          "dependency_count":\(dependencyCount),"dependent_count":\(dependentCount)}]
        """.data(using: .utf8)!
        return try BeadsService.decode(json)[0]
    }

    // MARK: - Size by Metric

    @Test("Zero dependents gives base size factor of 1.0")
    func zeroDepBaseSize() throws {
        let issue = try makeIssue(dependentCount: 0)
        #expect(NodeVisuals.sizeFactor(for: issue) == 1.0)
    }

    @Test("Size scales with dependent count")
    func sizeScalesWithDeps() throws {
        let small = try makeIssue(dependentCount: 1)
        let large = try makeIssue(dependentCount: 3)
        #expect(NodeVisuals.sizeFactor(for: large) > NodeVisuals.sizeFactor(for: small))
    }

    @Test("Size caps at maximum factor")
    func sizeMaxCap() throws {
        let huge = try makeIssue(dependentCount: 100)
        #expect(NodeVisuals.sizeFactor(for: huge) <= 1.6)
        #expect(NodeVisuals.sizeFactor(for: huge) >= 1.5)
    }

    // MARK: - Border Encoding

    @Test("Blocked issue gets blocked border color")
    func blockedBorder() throws {
        let blocker = try makeIssue(id: "b-1", status: "open")
        let blocked = try makeIssue(
            id: "a-1",
            dependencies: [(issueID: "a-1", dependsOnID: "b-1", type: "blocks")]
        )
        let color = NodeVisuals.borderColor(for: blocked, in: [blocked, blocker])
        #expect(color == Theme.statusBlocked)
    }

    @Test("Issue with all dependencies closed is not blocked")
    func closedDepsNotBlocked() throws {
        let closedDep = try makeIssue(id: "b-1", status: "closed")
        let issue = try makeIssue(
            id: "a-1",
            dependencies: [(issueID: "a-1", dependsOnID: "b-1", type: "blocks")]
        )
        let color = NodeVisuals.borderColor(for: issue, in: [issue, closedDep])
        #expect(color != Theme.statusBlocked)
    }

    @Test("Non-blocked open issue gets type color border")
    func openBorderUsesTypeColor() throws {
        let issue = try makeIssue(status: "open", issueType: "feature", dependentCount: 3)
        let color = NodeVisuals.borderColor(for: issue, in: [issue])
        #expect(color == Theme.typeFeature.opacity(0.6))
    }

    @Test("In-progress issue gets type color border")
    func inProgressBorderUsesTypeColor() throws {
        let issue = try makeIssue(status: "in_progress", issueType: "bug")
        let color = NodeVisuals.borderColor(for: issue, in: [issue])
        #expect(color == Theme.typeBug.opacity(0.6))
    }

    @Test("Closed issue gets type color border")
    func closedBorderUsesTypeColor() throws {
        let issue = try makeIssue(status: "closed", issueType: "task")
        let color = NodeVisuals.borderColor(for: issue, in: [issue])
        #expect(color == Theme.typeTask.opacity(0.6))
    }

    @Test("Blocked issue border width is 4x base")
    func blockedBorderWidth() throws {
        let blocker = try makeIssue(id: "b-1", status: "open")
        let blocked = try makeIssue(
            id: "a-1",
            dependencies: [(issueID: "a-1", dependsOnID: "b-1", type: "blocks")]
        )
        let width = NodeVisuals.borderWidth(for: blocked, in: [blocked, blocker])
        #expect(width == Theme.borderWidth * 4)
    }

    @Test("Non-blocked issue border width is 2x base")
    func nonBlockedBorderWidth() throws {
        let issue = try makeIssue(status: "open")
        let width = NodeVisuals.borderWidth(for: issue, in: [issue])
        #expect(width == Theme.borderWidth * 2)
    }

    // MARK: - Priority Badge

    @Test("Priority label matches issue priority")
    func priorityLabel() throws {
        let p0 = try makeIssue(priority: 0)
        #expect(NodeVisuals.priorityLabel(for: p0) == "P0")

        let p3 = try makeIssue(priority: 3)
        #expect(NodeVisuals.priorityLabel(for: p3) == "P3")
    }

    // MARK: - Age Indicator

    @Test("Fresh issue under 7 days gets green age color")
    func freshAge() throws {
        // Created "now" (test date context)
        let issue = try makeIssue(createdAt: ISO8601DateFormatter().string(from: Date()))
        let color = NodeVisuals.ageColor(for: issue)
        #expect(color == Theme.accent) // green
    }

    @Test("Closed issue has no age indicator")
    func closedNoAge() throws {
        let issue = try makeIssue(status: "closed")
        #expect(NodeVisuals.ageColor(for: issue) == nil)
    }

    @Test("Old issue over 30 days gets red age color")
    func oldAge() throws {
        let oldDate = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        let formatter = ISO8601DateFormatter()
        let issue = try makeIssue(createdAt: formatter.string(from: oldDate))
        let color = NodeVisuals.ageColor(for: issue)
        #expect(color == Theme.negative) // red
    }

    @Test("Medium-age issue 7-30 days gets yellow age color")
    func mediumAge() throws {
        let midDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        let formatter = ISO8601DateFormatter()
        let issue = try makeIssue(createdAt: formatter.string(from: midDate))
        let color = NodeVisuals.ageColor(for: issue)
        #expect(color == Theme.statusInProgress) // yellow
    }

    // MARK: - Type Color

    @Test("Bug type maps to typeBug color")
    func bugTypeColor() throws {
        let issue = try makeIssue(issueType: "bug")
        #expect(issue.typeColor == Theme.typeBug)
    }

    @Test("Task type maps to typeTask color")
    func taskTypeColor() throws {
        let issue = try makeIssue(issueType: "task")
        #expect(issue.typeColor == Theme.typeTask)
    }

    @Test("Feature type maps to typeFeature color")
    func featureTypeColor() throws {
        let issue = try makeIssue(issueType: "feature")
        #expect(issue.typeColor == Theme.typeFeature)
    }

    @Test("Epic type maps to typeEpic color")
    func epicTypeColor() throws {
        let issue = try makeIssue(issueType: "epic")
        #expect(issue.typeColor == Theme.typeEpic)
    }

    @Test("Unknown type maps to typeChore color")
    func unknownTypeColor() throws {
        let issue = try makeIssue(issueType: "mystery")
        #expect(issue.typeColor == Theme.typeChore)
    }

    // MARK: - Type Badge

    @Test("Bug type badge uses badgeBug colors")
    func bugTypeBadge() throws {
        let issue = try makeIssue(issueType: "bug")
        #expect(issue.typeBadge == Theme.badgeBug)
    }

    @Test("Task type badge uses badgeTask colors")
    func taskTypeBadge() throws {
        let issue = try makeIssue(issueType: "task")
        #expect(issue.typeBadge == Theme.badgeTask)
    }

    @Test("Feature type badge uses badgeFeature colors")
    func featureTypeBadge() throws {
        let issue = try makeIssue(issueType: "feature")
        #expect(issue.typeBadge == Theme.badgeFeature)
    }

    @Test("Epic type badge uses badgeEpic colors")
    func epicTypeBadge() throws {
        let issue = try makeIssue(issueType: "epic")
        #expect(issue.typeBadge == Theme.badgeEpic)
    }

    // MARK: - Status Badge

    @Test("Open status badge uses badgeOpen colors")
    func openStatusBadge() throws {
        let issue = try makeIssue(status: "open")
        #expect(issue.statusBadge == Theme.badgeOpen)
    }

    @Test("In-progress status badge uses badgeInProgress colors")
    func inProgressStatusBadge() throws {
        let issue = try makeIssue(status: "in_progress")
        #expect(issue.statusBadge == Theme.badgeInProgress)
    }

    @Test("Closed status badge uses badgeClosed colors")
    func closedStatusBadge() throws {
        let issue = try makeIssue(status: "closed")
        #expect(issue.statusBadge == Theme.badgeClosed)
    }

    @Test("Blocked status badge uses badgeBlocked colors")
    func blockedStatusBadge() throws {
        let issue = try makeIssue(status: "blocked")
        #expect(issue.statusBadge == Theme.badgeBlocked)
    }

    // MARK: - Owner Display

    @Test("Nil owner returns nil display")
    func nilOwnerDisplay() throws {
        let json = """
        [{"id":"t","title":"T","status":"open","priority":2,
          "issue_type":"task","created_at":"2026-01-01T00:00:00Z",
          "updated_at":"2026-01-01T00:00:00Z",
          "dependency_count":0,"dependent_count":0}]
        """.data(using: .utf8)!
        let issue = try BeadsService.decode(json)[0]
        #expect(issue.ownerDisplay == nil)
    }

    @Test("Simple name returns as-is when short enough")
    func simpleOwnerDisplay() throws {
        let json = """
        [{"id":"t","title":"T","status":"open","priority":2,
          "issue_type":"task","owner":"hex",
          "created_at":"2026-01-01T00:00:00Z",
          "updated_at":"2026-01-01T00:00:00Z",
          "dependency_count":0,"dependent_count":0}]
        """.data(using: .utf8)!
        let issue = try BeadsService.decode(json)[0]
        #expect(issue.ownerDisplay == "hex")
    }

    @Test("Email-style owner extracts first word")
    func emailOwnerDisplay() throws {
        let json = """
        [{"id":"t","title":"T","status":"open","priority":2,
          "issue_type":"task","owner":"hex@users.noreply.github.com",
          "created_at":"2026-01-01T00:00:00Z",
          "updated_at":"2026-01-01T00:00:00Z",
          "dependency_count":0,"dependent_count":0}]
        """.data(using: .utf8)!
        let issue = try BeadsService.decode(json)[0]
        #expect(issue.ownerDisplay == "hex")
    }

    @Test("Long first word truncates to 6 chars")
    func longOwnerDisplay() throws {
        let json = """
        [{"id":"t","title":"T","status":"open","priority":2,
          "issue_type":"task","owner":"Alexander Hamilton",
          "created_at":"2026-01-01T00:00:00Z",
          "updated_at":"2026-01-01T00:00:00Z",
          "dependency_count":0,"dependent_count":0}]
        """.data(using: .utf8)!
        let issue = try BeadsService.decode(json)[0]
        #expect(issue.ownerDisplay == "Alexan")
    }

    // MARK: - Dependency Count Label

    @Test("Issue with both deps and dependents shows both counts")
    func depCountBoth() throws {
        let issue = try makeIssue(dependentCount: 2, dependencyCount: 1)
        #expect(NodeVisuals.depCountLabel(for: issue) == "->2 <-1")
    }

    @Test("Issue with no deps or dependents returns nil")
    func depCountNone() throws {
        let issue = try makeIssue(dependentCount: 0, dependencyCount: 0)
        #expect(NodeVisuals.depCountLabel(for: issue) == nil)
    }

    @Test("Issue with only dependents shows only outgoing count")
    func depCountOnlyDependents() throws {
        let issue = try makeIssue(dependentCount: 3, dependencyCount: 0)
        #expect(NodeVisuals.depCountLabel(for: issue) == "->3")
    }

    @Test("Issue with only dependencies shows only incoming count")
    func depCountOnlyDependencies() throws {
        let issue = try makeIssue(dependentCount: 0, dependencyCount: 2)
        #expect(NodeVisuals.depCountLabel(for: issue) == "<-2")
    }
}
