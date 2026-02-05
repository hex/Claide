// ABOUTME: Status-based Kanban board displaying issues in four columns.
// ABOUTME: Columns: Open, Active, Blocked, Done. View-only, no drag-and-drop.

import SwiftUI

struct KanbanPanel: View {
    @Bindable var viewModel: GraphViewModel
    @State private var selectedIssueID: String?

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                Text(error)
                    .font(Theme.bodyFontSmall)
                    .foregroundStyle(Theme.negative)
                    .padding(Theme.panelPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.issues.isEmpty {
                EmptyStateView(dataSource: viewModel.dataSource)
            } else {
                boardContent
            }
        }
        .background(Theme.backgroundPrimary)
    }

    private var boardContent: some View {
        let grouped = KanbanColumn.groupByColumn(viewModel.issues)
        let columnCount = CGFloat(KanbanColumn.allCases.count)
        let spacing: CGFloat = 6
        let padding: CGFloat = 8

        return GeometryReader { geo in
            let columnWidth = max(140, (geo.size.width - padding * 2 - spacing * (columnCount - 1)) / columnCount)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(KanbanColumn.allCases, id: \.self) { column in
                        columnView(column, issues: grouped[column] ?? [], width: columnWidth)
                    }
                }
                .padding(padding)
            }
        }
    }

    private func columnView(_ column: KanbanColumn, issues: [Issue], width: CGFloat) -> some View {
        VStack(spacing: 0) {
            columnHeader(column, count: issues.count)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(issues) { issue in
                        cardView(issue, column: column)
                            .onTapGesture {
                                selectedIssueID = selectedIssueID == issue.id ? nil : issue.id
                            }
                            .popover(isPresented: Binding(
                                get: { selectedIssueID == issue.id },
                                set: { if !$0 { selectedIssueID = nil } }
                            )) {
                                IssueDetailPopover(issue: issue)
                            }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
        .frame(width: width)
        .background(Theme.backgroundPanel.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius))
    }

    private func columnHeader(_ column: KanbanColumn, count: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(for: column))
                .frame(width: 6, height: 6)
            Text(column.rawValue.uppercased())
                .font(Theme.labelFont)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.0)
            Spacer()
            Text("\(count)")
                .font(Theme.bodyFontSmall)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.backgroundPanel)
    }

    private func cardView(_ issue: Issue, column: KanbanColumn) -> some View {
        let stripeColor = column == .blocked ? Theme.statusBlocked : issue.typeColor
        return HStack(spacing: 0) {
            // Type-colored left stripe
            Rectangle()
                .fill(stripeColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                // Title
                Text(issue.title)
                    .font(Theme.bodyFontSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)

                // Priority + type
                HStack(spacing: 4) {
                    Text(NodeVisuals.priorityLabel(for: issue))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(issue.priorityColor)
                    Text(issue.issueType)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textMuted)
                }

                // Owner + dep count
                let owner = issue.ownerDisplay
                let depLabel = NodeVisuals.depCountLabel(for: issue)
                if owner != nil || depLabel != nil {
                    HStack(spacing: 4) {
                        if let owner {
                            Text(owner)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if let depLabel {
                            Text(depLabel)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(Theme.backgroundHover)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius))
    }

    private func statusColor(for column: KanbanColumn) -> Color {
        switch column {
        case .open: Theme.statusOpen
        case .inProgress: Theme.statusInProgress
        case .blocked: Theme.statusBlocked
        case .closed: Theme.statusClosed
        }
    }
}
