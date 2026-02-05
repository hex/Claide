// ABOUTME: Scrollable list showing recent file modifications from changes.md.
// ABOUTME: Each row displays timestamp, tool type, filename, and directory path.

import SwiftUI

struct FileLogPanel: View {
    @Bindable var viewModel: FileLogViewModel

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        PanelView {
            SectionHeader(title: "File Changes", trailing: "\(viewModel.changes.count) entries")

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

    private var changeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(viewModel.changes) { change in
                    changeRow(change)
                }
            }
        }
    }

    private func changeRow(_ change: FileChange) -> some View {
        HStack(spacing: 8) {
            // Timestamp
            Text(Self.timeFormatter.string(from: change.timestamp))
                .font(Theme.bodyFontSmall)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 55, alignment: .leading)

            // Tool badge
            Text(change.tool.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(toolColor(change.tool))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(toolColor(change.tool).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .frame(width: 50, alignment: .leading)

            // Filename
            VStack(alignment: .leading, spacing: 0) {
                Text(change.fileName)
                    .font(Theme.bodyFontSmall)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(change.directory)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Theme.backgroundPanel)
    }

    private func toolColor(_ tool: String) -> Color {
        switch tool.lowercased() {
        case "write": Theme.accent
        case "edit", "multiedit": Theme.statusInProgress
        case "read": Theme.statusOpen
        default: Theme.textSecondary
        }
    }
}
