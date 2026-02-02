// ABOUTME: Data model for a beads issue, decoded from `bd list --json` output.
// ABOUTME: Includes nested dependency edges and computed status color.

import SwiftUI

struct Issue: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String?
    let status: String
    let priority: Int
    let issueType: String
    let owner: String?
    let createdAt: String
    let createdBy: String?
    let updatedAt: String
    let dependencies: [IssueDependency]?
    let dependencyCount: Int
    let dependentCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, priority, owner, dependencies
        case issueType = "issue_type"
        case createdAt = "created_at"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case dependencyCount = "dependency_count"
        case dependentCount = "dependent_count"
    }

    var statusColor: Color {
        switch status {
        case "open": Theme.statusOpen
        case "in_progress": Theme.statusInProgress
        case "blocked": Theme.statusBlocked
        case "closed": Theme.statusClosed
        default: Theme.textMuted
        }
    }

    var priorityColor: Color {
        switch priority {
        case 0: Theme.priorityCritical
        case 1: Theme.priorityHigh
        case 2: Theme.priorityMedium
        case 3: Theme.priorityLow
        case 4: Theme.priorityBacklog
        default: Theme.textMuted
        }
    }

    var typeColor: Color {
        switch issueType {
        case "bug": Theme.typeBug
        case "task": Theme.typeTask
        case "feature": Theme.typeFeature
        case "epic": Theme.typeEpic
        default: Theme.typeChore
        }
    }

    var typeBadge: BadgeColors {
        switch issueType {
        case "bug": Theme.badgeBug
        case "task": Theme.badgeTask
        case "feature": Theme.badgeFeature
        case "epic": Theme.badgeEpic
        default: Theme.badgeChore
        }
    }

    var statusBadge: BadgeColors {
        switch status {
        case "open": Theme.badgeOpen
        case "in_progress": Theme.badgeInProgress
        case "closed": Theme.badgeClosed
        case "blocked": Theme.badgeBlocked
        default: Theme.badgeOpen
        }
    }

    var priorityBadge: BadgeColors {
        switch priority {
        case 0: Theme.badgeCritical
        case 1: Theme.badgeHigh
        case 2: Theme.badgeMedium
        case 3: Theme.badgeLow
        case 4: Theme.badgeBacklog
        default: Theme.badgeMedium
        }
    }

    /// Short display name from owner: first word, max 6 characters.
    var ownerDisplay: String? {
        guard let owner, !owner.isEmpty else { return nil }
        let first = owner.split(separator: "@").first.flatMap { String($0) }
            ?? owner.split(separator: " ").first.flatMap { String($0) }
            ?? owner
        return String(first.prefix(6))
    }

    /// All issue IDs this issue depends on (via "blocks" type dependencies)
    var blockedByIDs: [String] {
        (dependencies ?? [])
            .filter { $0.type == "blocks" && $0.issueID == id }
            .map(\.dependsOnID)
    }
}
