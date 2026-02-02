// ABOUTME: Assigns issues to Kanban board columns based on status and dependency state.
// ABOUTME: Priority: closed > blocked-by-dep-or-status > in_progress > open.

enum KanbanColumn: String, CaseIterable, Sendable {
    case open = "Open"
    case inProgress = "Active"
    case blocked = "Blocked"
    case closed = "Done"

    /// Assign a single issue to its column based on status and blockers.
    /// Priority: closed first, then blocked (by status or open dependencies),
    /// then in_progress, everything else is open.
    static func assign(issue: Issue, in allIssues: [Issue]) -> KanbanColumn {
        if issue.status == "closed" { return .closed }
        if issue.status == "blocked" || NodeVisuals.isBlocked(issue, in: allIssues) {
            return .blocked
        }
        if issue.status == "in_progress" { return .inProgress }
        return .open
    }

    /// Group issues into columns. Every column key is present (possibly empty).
    static func groupByColumn(_ issues: [Issue]) -> [KanbanColumn: [Issue]] {
        var result: [KanbanColumn: [Issue]] = [:]
        for col in KanbanColumn.allCases { result[col] = [] }
        for issue in issues {
            let col = assign(issue: issue, in: issues)
            result[col, default: []].append(issue)
        }
        return result
    }
}
