// ABOUTME: Friendly placeholder shown when no issues or tasks are loaded.
// ABOUTME: Data-source-aware messaging with setup hints.

import SwiftUI

struct EmptyStateView: View {
    let dataSource: DataSource

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 28))
                .foregroundStyle(Theme.textMuted.opacity(0.5))

            Text(title)
                .font(Theme.labelFont)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.5)

            Text(subtitle)
                .font(Theme.monoFontSmall)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)

            if let hint {
                Text(hint)
                    .font(Theme.monoFontSmall)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.backgroundSunken)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconName: String {
        switch dataSource {
        case .beads: "circle.hexagongrid"
        case .claudeCode: "checklist"
        }
    }

    private var title: String {
        switch dataSource {
        case .beads: "NO ISSUES"
        case .claudeCode: "NO TASKS"
        }
    }

    private var subtitle: String {
        switch dataSource {
        case .beads: "Track work with beads issue management"
        case .claudeCode: "Tasks from Claude Code sessions appear here"
        }
    }

    private var hint: String? {
        switch dataSource {
        case .beads: "$ bd init"
        case .claudeCode: nil
        }
    }
}
