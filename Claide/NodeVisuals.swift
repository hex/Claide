// ABOUTME: Computes visual properties for graph nodes from issue data.
// ABOUTME: Maps dependent count to size, blocked status to border, and age to indicator color.

import SwiftUI

enum NodeVisuals {

    // MARK: - Size

    /// Scale factor based on how many other issues depend on this one.
    /// Range: 1.0 (no dependents) to 1.6 (4+ dependents).
    static func sizeFactor(for issue: Issue) -> CGFloat {
        1.0 + 0.15 * CGFloat(min(issue.dependentCount, 4))
    }

    // MARK: - Border Color

    /// Border color: blocked issues get red, everything else uses type color at 60% opacity.
    static func borderColor(for issue: Issue, in allIssues: [Issue]) -> Color {
        if isBlocked(issue, in: allIssues) {
            return Theme.statusBlocked
        }
        return issue.typeColor.opacity(0.6)
    }

    /// Border width: blocked issues 4x base, everything else 2x base.
    static func borderWidth(for issue: Issue, in allIssues: [Issue]) -> CGFloat {
        if isBlocked(issue, in: allIssues) {
            return Theme.borderWidth * 4
        }
        return Theme.borderWidth * 2
    }

    // MARK: - Blocked Detection

    /// An issue is blocked if it depends on (via "blocks" type) any issue that isn't closed.
    static func isBlocked(_ issue: Issue, in allIssues: [Issue]) -> Bool {
        let blockerIDs = issue.blockedByIDs
        guard !blockerIDs.isEmpty else { return false }
        let statusByID = Dictionary(uniqueKeysWithValues: allIssues.map { ($0.id, $0.status) })
        return blockerIDs.contains { id in
            guard let status = statusByID[id] else { return false }
            return status != "closed"
        }
    }

    // MARK: - Priority Badge

    static func priorityLabel(for issue: Issue) -> String {
        "P\(issue.priority)"
    }

    // MARK: - Dependency Count Label

    /// Compact dependency summary: "->2 <-1" for dependents/dependencies, nil if both zero.
    static func depCountLabel(for issue: Issue) -> String? {
        let out = issue.dependentCount
        let inc = issue.dependencyCount
        guard out > 0 || inc > 0 else { return nil }
        var parts: [String] = []
        if out > 0 { parts.append("->\(out)") }
        if inc > 0 { parts.append("<-\(inc)") }
        return parts.joined(separator: " ")
    }

    // MARK: - Age Indicator

    /// Color indicating issue age. Nil for closed issues.
    /// Green (<7 days), yellow (7-30 days), red (>30 days).
    static func ageColor(for issue: Issue) -> Color? {
        guard issue.status != "closed" else { return nil }
        guard let days = ageInDays(for: issue) else { return nil }
        if days < 7 { return Theme.accent }
        if days <= 30 { return Theme.statusInProgress }
        return Theme.negative
    }

    /// Parse createdAt and compute days since creation.
    static func ageInDays(for issue: Issue) -> Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: issue.createdAt)
        if date == nil {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: issue.createdAt)
        }
        guard let created = date else { return nil }
        return Calendar.current.dateComponents([.day], from: created, to: Date()).day
    }
}
