// ABOUTME: Scrollable list showing file operations from transcript and git working tree.
// ABOUTME: Groups changes by source with accent bars, badges, and hover states.

import SwiftUI

struct FileLogPanel: View {
    @Bindable var viewModel: FileLogViewModel
    @State private var hoveredId: UUID?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    private var activityChanges: [FileChange] {
        viewModel.changes.filter { $0.source == .transcript }
    }

    private var workingTreeChanges: [FileChange] {
        viewModel.changes
            .filter { $0.source == .git }
            .sorted { $0.fileName.localizedCompare($1.fileName) == .orderedAscending }
    }

    var body: some View {
        PanelView {
            SectionHeader(title: "Files", trailing: "\(viewModel.changes.count)")

            if let error = viewModel.error {
                Text(error)
                    .font(Theme.bodyFontSmall)
                    .foregroundStyle(Theme.negative)
            } else if viewModel.changes.isEmpty {
                Text("No file changes recorded")
                    .font(Theme.bodyFontSmall)
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                changeList
            }
        }
    }

    // MARK: - List

    private var changeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if !activityChanges.isEmpty {
                    sectionLabel("ACTIVITY", count: activityChanges.count)
                    ForEach(activityChanges) { change in
                        changeRow(change, showTimestamp: true)
                    }
                }

                if !workingTreeChanges.isEmpty {
                    sectionLabel("WORKING TREE", count: workingTreeChanges.count)
                    ForEach(workingTreeChanges) { change in
                        changeRow(change, showTimestamp: false)
                    }
                }
            }
        }
    }

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .tracking(1.5)
            Spacer()
            Text("\(count)")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: - Row

    private func changeRow(_ change: FileChange, showTimestamp: Bool) -> some View {
        HStack(spacing: 6) {
            badge(change)
            fileInfo(change)
            Spacer(minLength: 4)

            if showTimestamp {
                Text(Self.timeFormatter.string(from: change.timestamp))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(hoveredId == change.id ? Theme.backgroundHover : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(Tooltip(rowTooltip(change)).allowsHitTesting(false))
        .onHover { hovering in hoveredId = hovering ? change.id : nil }
    }

    private func badge(_ change: FileChange) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(toolColor(change.tool).opacity(0.15))
            Text(badgeLabel(change.tool))
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(toolColor(change.tool))
        }
        .frame(width: 18, height: 14)
    }

    private func fileInfo(_ change: FileChange) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(change.fileName)
                .font(Theme.bodyFontSmall)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            HStack(spacing: 2) {
                Image(systemName: change.source == .transcript ? "sparkles" : "person")
                    .font(.system(size: 7))
                    .foregroundStyle(change.source == .transcript ? Theme.statusOpen : Theme.textMuted)

                Text(change.directory)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }

    // MARK: - Tooltip

    private func rowTooltip(_ change: FileChange) -> String {
        let source = change.source == .transcript ? "Claude Code" : "Local"
        let date = Self.fullDateFormatter.string(from: change.timestamp)
        return "\(change.tool) — \(source)\n\(date)\n\(change.filePath)"
    }

    // MARK: - Badge Helpers

    private func badgeLabel(_ tool: String) -> String {
        switch tool.lowercased() {
        case "write": "W"
        case "edit": "E"
        case "multiedit": "E"
        case "read": "R"
        case "modified": "M"
        case "added": "A"
        case "deleted": "D"
        case "untracked": "?"
        case "renamed": "R"
        case "copied": "C"
        case "conflict": "!"
        default: tool.prefix(1).uppercased()
        }
    }

    private func toolColor(_ tool: String) -> Color {
        switch tool.lowercased() {
        // Transcript operations
        case "write": Theme.accent
        case "edit", "multiedit": Theme.statusInProgress
        case "read": Theme.statusOpen
        // Git status
        case "modified": Theme.priorityHigh
        case "added": Theme.accent
        case "deleted": Theme.negative
        case "untracked": Theme.textMuted
        case "renamed", "copied": Theme.statusOpen
        case "conflict": Theme.statusBlocked
        default: Theme.textSecondary
        }
    }
}
