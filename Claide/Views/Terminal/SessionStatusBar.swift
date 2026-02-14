// ABOUTME: Displays context window token usage at the bottom of the terminal section.
// ABOUTME: Color shifts green → yellow → orange → red as usage approaches compaction threshold.

import SwiftUI

struct SessionStatusBar: View {
    let status: SessionStatus?
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"

    private static let barHeight: CGFloat = 2

    var body: some View {
        let _ = schemeName
        if let status {
            HStack {
                Text("\(SessionStatus.shortTokenCount(status.remainingTokens)) remaining")
                    .font(Theme.bodyFontSmall)
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

    /// Smooth green → yellow → orange → red gradient. Turns toward red past 60%.
    private func usageColor(percentage: Double) -> Color {
        let t = min(max(percentage / 100, 0), 1)
        let hue: Double
        if t < 0.6 {
            // Green (0.33) → orange (0.08) over 0–60%
            hue = 0.33 - (0.33 - 0.08) * (t / 0.6)
        } else {
            // Orange (0.08) → red (0.0) over 60–100%
            hue = 0.08 * (1 - (t - 0.6) / 0.4)
        }
        return Color(hue: hue, saturation: 0.75, brightness: 0.85)
    }
}
