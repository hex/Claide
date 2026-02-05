// ABOUTME: Compact detail view for displaying all fields of a single beads issue.
// ABOUTME: Used in popovers from both Kanban cards and Graph nodes.

import SwiftUI

struct IssueDetailPopover: View {
    let issue: Issue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            divider
            titleRow
            if let description = issue.description, !description.isEmpty {
                divider
                descriptionRow(description)
            }
            divider
            detailRows
        }
        .frame(width: 280)
        .background(Theme.backgroundPanel)
        .preferredColorScheme(.dark)
    }

    private var headerRow: some View {
        HStack {
            Text(issue.id)
                .font(Theme.bodyFont)
                .foregroundStyle(issue.typeColor)
            Spacer()
            Text(issue.issueType.capitalized)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(issue.typeBadge.fg)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(issue.typeBadge.bg)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(issue.typeBadge.border, lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var titleRow: some View {
        Text(issue.title)
            .font(Theme.headingFont)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private func descriptionRow(_ text: String) -> some View {
        Text(text)
            .font(Theme.bodyFontSmall)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(4)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 0.5)
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            detailRow("STATUS", value: Self.statusText(for: issue.status), color: issue.statusColor)
            detailRow("PRIORITY", value: Self.priorityText(for: issue.priority), color: issue.priorityColor)
            if let owner = issue.owner, !owner.isEmpty {
                detailRow("OWNER", value: owner)
            }
            detailRow("CREATED", value: Self.formatDate(issue.createdAt))
            detailRow("UPDATED", value: Self.formatDate(issue.updatedAt))
            if let depLabel = NodeVisuals.depCountLabel(for: issue) {
                detailRow("DEPS", value: depLabel)
            }
            if let blockedBy = Self.blockedByText(for: issue) {
                detailRow("BLOCKED", value: blockedBy, color: Theme.statusBlocked)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func detailRow(_ label: String, value: String, color: Color = Theme.textPrimary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(Theme.bodyFontSmall)
                .foregroundStyle(color)
                .lineLimit(2)
        }
    }

    // MARK: - Formatting Helpers

    static func priorityText(for priority: Int) -> String {
        let name: String
        switch priority {
        case 0: name = "Critical"
        case 1: name = "High"
        case 2: name = "Medium"
        case 3: name = "Low"
        case 4: name = "Backlog"
        default: name = "Unknown"
        }
        return "P\(priority) \(name)"
    }

    static func statusText(for status: String) -> String {
        switch status {
        case "in_progress": "Active"
        default: status.capitalized
        }
    }

    static func formatDate(_ isoString: String) -> String {
        guard let tIndex = isoString.firstIndex(of: "T") else { return isoString }
        return String(isoString[isoString.startIndex..<tIndex])
    }

    static func blockedByText(for issue: Issue) -> String? {
        let ids = issue.blockedByIDs
        guard !ids.isEmpty else { return nil }
        return ids.joined(separator: ", ")
    }
}
