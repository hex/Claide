// ABOUTME: Displays context window token usage at the bottom of the terminal section.
// ABOUTME: Color shifts from muted to warning as usage approaches compaction threshold.

import SwiftUI

struct SessionStatusBar: View {
    let status: SessionStatus?

    private static let barHeight: CGFloat = 2

    var body: some View {
        if let status {
            HStack {
                Text(status.formattedUsage)
                    .font(Theme.monoFontSmall)
                    .foregroundStyle(usageColor(percentage: status.usedPercentage))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Theme.backgroundPanel)
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.border)
                        Rectangle()
                            .fill(usageColor(percentage: status.usedPercentage))
                            .frame(width: geo.size.width * min(status.usedPercentage / 100, 1))
                    }
                }
                .frame(height: Self.barHeight)
            }
        }
    }

    /// Muted below 60%, yellow approaching compaction, red past threshold.
    private func usageColor(percentage: Double) -> Color {
        switch percentage {
        case ..<60:  Theme.textMuted
        case ..<80:  Theme.statusInProgress
        default:     Theme.statusBlocked
        }
    }
}
