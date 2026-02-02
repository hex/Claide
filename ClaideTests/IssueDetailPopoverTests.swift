// ABOUTME: Tests for issue detail popover formatting and initialization.
// ABOUTME: Validates priority text, status text, date formatting, and edge cases.

import Testing
import SwiftUI
@testable import Claide

@Suite("Issue Detail Popover")
@MainActor
struct IssueDetailPopoverTests {

    // MARK: - Test Helpers

    private func makeIssue(
        id: String = "t-1",
        title: String = "Test Issue",
        description: String? = "A description",
        status: String = "open",
        priority: Int = 2,
        issueType: String = "task",
        owner: String? = "hex",
        createdAt: String = "2026-01-30T14:52:09.546661+02:00",
        updatedAt: String = "2026-02-01T10:00:00Z",
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
        let descJSON = description.map { "\"\($0)\"" } ?? "null"
        let ownerJSON = owner.map { "\"\($0)\"" } ?? "null"
        let json = """
        [{"id":"\(id)","title":"\(title)","description":\(descJSON),
          "status":"\(status)","priority":\(priority),
          "issue_type":"\(issueType)","owner":\(ownerJSON),
          "created_at":"\(createdAt)",
          "updated_at":"\(updatedAt)",
          "dependencies":\(depJSON),
          "dependency_count":\(dependencyCount),"dependent_count":\(dependentCount)}]
        """.data(using: .utf8)!
        return try BeadsService.decode(json)[0]
    }

    // MARK: - View Creation (smoke tests)

    @Test("Creates without crash for full issue")
    func fullIssue() throws {
        let issue = try makeIssue()
        let view = IssueDetailPopover(issue: issue)
        #expect(type(of: view) == IssueDetailPopover.self)
    }

    @Test("Creates without crash for nil description")
    func nilDescription() throws {
        let issue = try makeIssue(description: nil)
        let view = IssueDetailPopover(issue: issue)
        #expect(type(of: view) == IssueDetailPopover.self)
    }

    @Test("Creates without crash for nil owner")
    func nilOwner() throws {
        let issue = try makeIssue(owner: nil)
        let view = IssueDetailPopover(issue: issue)
        #expect(type(of: view) == IssueDetailPopover.self)
    }

    @Test("Creates without crash for closed issue with no optional fields")
    func closedMinimal() throws {
        let issue = try makeIssue(description: nil, status: "closed", owner: nil)
        let view = IssueDetailPopover(issue: issue)
        #expect(type(of: view) == IssueDetailPopover.self)
    }

    // MARK: - Priority Text

    @Test("Priority text for P0")
    func priorityP0() {
        #expect(IssueDetailPopover.priorityText(for: 0) == "P0 Critical")
    }

    @Test("Priority text for P1")
    func priorityP1() {
        #expect(IssueDetailPopover.priorityText(for: 1) == "P1 High")
    }

    @Test("Priority text for P2")
    func priorityP2() {
        #expect(IssueDetailPopover.priorityText(for: 2) == "P2 Medium")
    }

    @Test("Priority text for P3")
    func priorityP3() {
        #expect(IssueDetailPopover.priorityText(for: 3) == "P3 Low")
    }

    @Test("Priority text for P4")
    func priorityP4() {
        #expect(IssueDetailPopover.priorityText(for: 4) == "P4 Backlog")
    }

    // MARK: - Status Text

    @Test("Status text for in_progress shows Active")
    func statusActive() {
        #expect(IssueDetailPopover.statusText(for: "in_progress") == "Active")
    }

    @Test("Status text for open shows Open")
    func statusOpen() {
        #expect(IssueDetailPopover.statusText(for: "open") == "Open")
    }

    @Test("Status text for closed shows Closed")
    func statusClosed() {
        #expect(IssueDetailPopover.statusText(for: "closed") == "Closed")
    }

    @Test("Status text for blocked shows Blocked")
    func statusBlocked() {
        #expect(IssueDetailPopover.statusText(for: "blocked") == "Blocked")
    }

    // MARK: - Date Formatting

    @Test("Formats ISO8601 date with timezone to date-only string")
    func formatDateWithTimezone() {
        #expect(IssueDetailPopover.formatDate("2026-01-30T14:52:09.546661+02:00") == "2026-01-30")
    }

    @Test("Formats ISO8601 date with Z suffix to date-only string")
    func formatDateWithZ() {
        #expect(IssueDetailPopover.formatDate("2026-02-01T10:00:00Z") == "2026-02-01")
    }

    @Test("Returns raw string for unparseable date")
    func formatDateInvalid() {
        #expect(IssueDetailPopover.formatDate("not-a-date") == "not-a-date")
    }

    // MARK: - Blocked By Text

    @Test("Blocked-by text is nil when no blockers")
    func noBlockers() throws {
        let issue = try makeIssue()
        #expect(IssueDetailPopover.blockedByText(for: issue) == nil)
    }

    @Test("Blocked-by text lists blocker IDs")
    func hasBlockers() throws {
        let issue = try makeIssue(
            id: "a-1",
            dependencies: [
                (issueID: "a-1", dependsOnID: "b-1", type: "blocks"),
                (issueID: "a-1", dependsOnID: "b-2", type: "blocks"),
            ]
        )
        #expect(IssueDetailPopover.blockedByText(for: issue) == "b-1, b-2")
    }
}
