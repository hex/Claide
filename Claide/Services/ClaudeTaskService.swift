// ABOUTME: Reads Claude Code task files from ~/.claude/tasks/ and converts them to Issue models.
// ABOUTME: Detects task list availability via the CLAUDE_CODE_TASK_LIST_ID environment variable.

import Foundation

struct ClaudeTaskService: Sendable {

    /// The task list ID from environment, if available
    static var taskListID: String? {
        ProcessInfo.processInfo.environment["CLAUDE_CODE_TASK_LIST_ID"]
    }

    /// Whether Claude Code tasks are available
    static var isAvailable: Bool {
        taskListID != nil
    }

    /// Load tasks and convert to Issue models
    static func loadIssues() throws -> [Issue] {
        guard let id = taskListID else { return [] }
        let dir = tasksDirectory(for: id)

        let fm = FileManager.default
        guard fm.fileExists(atPath: dir) else { return [] }

        let contents = try fm.contentsOfDirectory(atPath: dir)
        let jsonFiles = contents.filter { $0.hasSuffix(".json") }.sorted()

        let decoder = JSONDecoder()
        var issues: [Issue] = []

        for file in jsonFiles {
            let path = (dir as NSString).appendingPathComponent(file)
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let task = try decoder.decode(RawTask.self, from: data)
            issues.append(task.toIssue())
        }

        return issues
    }

    // MARK: - Private

    private static func tasksDirectory(for id: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent(".claude/tasks/\(id)")
    }
}

// MARK: - JSON Model

extension ClaudeTaskService {
    struct RawTask: Codable, Sendable {
        let id: String
        let subject: String
        let description: String?
        let activeForm: String?
        let status: String
        let blocks: [String]?
        let blockedBy: [String]?

        func toIssue() -> Issue {
            let mappedStatus: String = switch status {
            case "pending": "open"
            case "in_progress": "in_progress"
            case "completed": "closed"
            default: status
            }

            // Build dependencies from blockedBy relationships
            var deps: [IssueDependency] = []
            for blockerID in blockedBy ?? [] {
                deps.append(IssueDependency(
                    issueID: id,
                    dependsOnID: blockerID,
                    type: "blocks",
                    createdAt: "",
                    createdBy: ""
                ))
            }

            let now = ISO8601DateFormatter().string(from: Date())

            return Issue(
                id: id,
                title: subject,
                description: description,
                status: mappedStatus,
                priority: 2,
                issueType: "task",
                owner: nil,
                createdAt: now,
                createdBy: nil,
                updatedAt: now,
                dependencies: deps.isEmpty ? nil : deps,
                dependencyCount: (blockedBy ?? []).count,
                dependentCount: (blocks ?? []).count
            )
        }
    }
}
