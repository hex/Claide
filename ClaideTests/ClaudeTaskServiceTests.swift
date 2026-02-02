// ABOUTME: Tests for ClaudeTaskService JSON parsing and Issue conversion.
// ABOUTME: Verifies status mapping, dependency wiring, and empty-directory handling.

import Testing
import Foundation
@testable import Claide

@Suite("Claude Task Service")
struct ClaudeTaskServiceTests {

    // MARK: - JSON Parsing

    @Test("decodes a pending task with no dependencies")
    func decodePendingTask() throws {
        let json = """
        {
            "id": "1",
            "subject": "Fix login bug",
            "description": "Users can't log in",
            "activeForm": "Fixing login bug",
            "status": "pending",
            "blocks": [],
            "blockedBy": []
        }
        """
        let task = try JSONDecoder().decode(ClaudeTaskService.RawTask.self, from: Data(json.utf8))
        let issue = task.toIssue()

        #expect(issue.id == "1")
        #expect(issue.title == "Fix login bug")
        #expect(issue.description == "Users can't log in")
        #expect(issue.status == "open")
        #expect(issue.priority == 2)
        #expect(issue.issueType == "task")
        #expect(issue.dependencyCount == 0)
        #expect(issue.dependentCount == 0)
    }

    @Test("maps in_progress status correctly")
    func decodeInProgressTask() throws {
        let json = """
        {
            "id": "2",
            "subject": "Add caching",
            "status": "in_progress",
            "blocks": [],
            "blockedBy": []
        }
        """
        let task = try JSONDecoder().decode(ClaudeTaskService.RawTask.self, from: Data(json.utf8))
        let issue = task.toIssue()

        #expect(issue.status == "in_progress")
        #expect(issue.description == nil)
    }

    @Test("maps completed status to closed")
    func decodeCompletedTask() throws {
        let json = """
        {
            "id": "3",
            "subject": "Write docs",
            "status": "completed",
            "blocks": [],
            "blockedBy": []
        }
        """
        let task = try JSONDecoder().decode(ClaudeTaskService.RawTask.self, from: Data(json.utf8))
        let issue = task.toIssue()

        #expect(issue.status == "closed")
    }

    @Test("converts blockedBy into issue dependencies")
    func decodeBlockedTask() throws {
        let json = """
        {
            "id": "5",
            "subject": "Deploy app",
            "status": "pending",
            "blocks": [],
            "blockedBy": ["3", "4"]
        }
        """
        let task = try JSONDecoder().decode(ClaudeTaskService.RawTask.self, from: Data(json.utf8))
        let issue = task.toIssue()

        #expect(issue.dependencyCount == 2)
        #expect(issue.dependencies?.count == 2)
        #expect(issue.blockedByIDs.contains("3"))
        #expect(issue.blockedByIDs.contains("4"))
    }

    @Test("tracks dependent count from blocks array")
    func decodeDependentCount() throws {
        let json = """
        {
            "id": "1",
            "subject": "Core feature",
            "status": "pending",
            "blocks": ["2", "3", "4"],
            "blockedBy": []
        }
        """
        let task = try JSONDecoder().decode(ClaudeTaskService.RawTask.self, from: Data(json.utf8))
        let issue = task.toIssue()

        #expect(issue.dependentCount == 3)
        #expect(issue.dependencyCount == 0)
    }

    @Test("handles missing optional fields gracefully")
    func decodeMinimalTask() throws {
        let json = """
        {
            "id": "1",
            "subject": "Minimal",
            "status": "pending"
        }
        """
        let task = try JSONDecoder().decode(ClaudeTaskService.RawTask.self, from: Data(json.utf8))
        let issue = task.toIssue()

        #expect(issue.id == "1")
        #expect(issue.title == "Minimal")
        #expect(issue.description == nil)
        #expect(issue.owner == nil)
        #expect(issue.dependencies == nil)
        #expect(issue.dependencyCount == 0)
        #expect(issue.dependentCount == 0)
    }

    // MARK: - File Loading

    @Test("loadIssues returns empty when no task list ID set")
    func loadIssuesWithoutEnvVar() throws {
        // When CLAUDE_CODE_TASK_LIST_ID is not set in the test environment,
        // the service should return an empty array (not crash)
        // Note: In CI/test environments this env var is typically unset
        if ClaudeTaskService.taskListID == nil {
            let issues = try ClaudeTaskService.loadIssues()
            #expect(issues.isEmpty)
        }
    }
}
