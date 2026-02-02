// ABOUTME: Tests for Kanban column assignment logic.
// ABOUTME: Validates that issues are categorized into the correct board column by status and dependencies.

import Testing
@testable import Claide

@Suite("Kanban Column Assignment")
struct KanbanColumnTests {

    // MARK: - Test Helpers

    private func makeIssue(
        id: String = "t-1",
        title: String = "Test",
        status: String = "open",
        priority: Int = 2,
        issueType: String = "task",
        owner: String? = nil,
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
        let ownerJSON = owner.map { "\"\($0)\"" } ?? "null"
        let json = """
        [{"id":"\(id)","title":"\(title)","status":"\(status)","priority":\(priority),
          "issue_type":"\(issueType)","owner":\(ownerJSON),
          "created_at":"2026-02-01T00:00:00Z",
          "updated_at":"2026-02-01T00:00:00Z",
          "dependencies":\(depJSON),
          "dependency_count":\(dependencyCount),"dependent_count":\(dependentCount)}]
        """.data(using: .utf8)!
        return try BeadsService.decode(json)[0]
    }

    // MARK: - Single Issue Assignment

    @Test("Open issue goes to open column")
    func openIssue() throws {
        let issue = try makeIssue(status: "open")
        #expect(KanbanColumn.assign(issue: issue, in: [issue]) == .open)
    }

    @Test("In-progress issue goes to inProgress column")
    func inProgressIssue() throws {
        let issue = try makeIssue(status: "in_progress")
        #expect(KanbanColumn.assign(issue: issue, in: [issue]) == .inProgress)
    }

    @Test("Closed issue goes to closed column")
    func closedIssue() throws {
        let issue = try makeIssue(status: "closed")
        #expect(KanbanColumn.assign(issue: issue, in: [issue]) == .closed)
    }

    @Test("Issue with blocked status goes to blocked column")
    func blockedByStatus() throws {
        let issue = try makeIssue(status: "blocked")
        #expect(KanbanColumn.assign(issue: issue, in: [issue]) == .blocked)
    }

    // MARK: - Dependency-Based Blocking

    @Test("Open issue with open blocker goes to blocked column")
    func openWithOpenBlocker() throws {
        let blocker = try makeIssue(id: "b-1", status: "open")
        let issue = try makeIssue(
            id: "a-1",
            status: "open",
            dependencies: [(issueID: "a-1", dependsOnID: "b-1", type: "blocks")]
        )
        #expect(KanbanColumn.assign(issue: issue, in: [issue, blocker]) == .blocked)
    }

    @Test("In-progress issue with open blocker goes to blocked column")
    func inProgressWithOpenBlocker() throws {
        let blocker = try makeIssue(id: "b-1", status: "open")
        let issue = try makeIssue(
            id: "a-1",
            status: "in_progress",
            dependencies: [(issueID: "a-1", dependsOnID: "b-1", type: "blocks")]
        )
        #expect(KanbanColumn.assign(issue: issue, in: [issue, blocker]) == .blocked)
    }

    @Test("Issue with all blockers closed goes to its status column, not blocked")
    func allBlockersClosed() throws {
        let closedBlocker = try makeIssue(id: "b-1", status: "closed")
        let issue = try makeIssue(
            id: "a-1",
            status: "in_progress",
            dependencies: [(issueID: "a-1", dependsOnID: "b-1", type: "blocks")]
        )
        #expect(KanbanColumn.assign(issue: issue, in: [issue, closedBlocker]) == .inProgress)
    }

    // MARK: - groupByColumn

    @Test("groupByColumn returns correct distribution for mixed issue set")
    func groupByColumn() throws {
        let openIssue = try makeIssue(id: "i-1", status: "open")
        let wipIssue = try makeIssue(id: "i-2", status: "in_progress")
        let closedIssue = try makeIssue(id: "i-3", status: "closed")
        let blockedIssue = try makeIssue(id: "i-4", status: "blocked")
        let blockerTarget = try makeIssue(id: "i-5", status: "open")
        let depBlocked = try makeIssue(
            id: "i-6",
            status: "in_progress",
            dependencies: [(issueID: "i-6", dependsOnID: "i-5", type: "blocks")]
        )

        let allIssues = [openIssue, wipIssue, closedIssue, blockedIssue, blockerTarget, depBlocked]
        let grouped = KanbanColumn.groupByColumn(allIssues)

        #expect(grouped[.open]?.count == 2)        // i-1 + i-5
        #expect(grouped[.inProgress]?.count == 1)   // i-2
        #expect(grouped[.blocked]?.count == 2)      // i-4 + i-6
        #expect(grouped[.closed]?.count == 1)       // i-3
    }
}
