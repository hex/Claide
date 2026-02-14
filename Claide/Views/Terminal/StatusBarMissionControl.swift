// ABOUTME: "Mission Control" status bar — info-dense, segmented left/center/right layout.
// ABOUTME: Shows model, token breakdown, session metrics in distinct zones like VS Code.

import SwiftUI

struct StatusBarMissionControl: View {
    let status: SessionStatus?
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"

    var body: some View {
        let _ = schemeName
        if let status {
            HStack(spacing: 0) {
                // Left zone: model info
                leftZone(status: status)

                zoneDivider

                Spacer()

                // Center zone: context usage (the hero metric)
                centerZone(status: status)

                Spacer()

                zoneDivider

                // Right zone: token breakdown
                rightZone(status: status)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.backgroundSunken)
            .overlay(alignment: .top) {
                // Thin progress line at top edge
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.border)
                        Rectangle()
                            .fill(usageColor(percentage: status.usedPercentage))
                            .frame(width: geo.size.width * min(status.usedPercentage / 100, 1))
                    }
                }
                .frame(height: 2)
            }
        }
    }

    // MARK: - Zones

    @ViewBuilder
    private func leftZone(status: SessionStatus) -> some View {
        HStack(spacing: 6) {
            // Model indicator dot
            Circle()
                .fill(Palette.color(.uiGreen))
                .frame(width: 6, height: 6)

            Text(status.modelDisplayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Text("\(status.contextWindowSize / 1000)K")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    @ViewBuilder
    private func centerZone(status: SessionStatus) -> some View {
        HStack(spacing: 6) {
            // Remaining tokens as the primary metric
            Text(SessionStatus.shortTokenCount(status.remainingTokens))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(usageColor(percentage: status.usedPercentage))

            Text("remaining")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textMuted)
        }
    }

    @ViewBuilder
    private func rightZone(status: SessionStatus) -> some View {
        tokenLabel(label: "OUT", value: status.outputTokens)
    }

    @ViewBuilder
    private func tokenLabel(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Text(SessionStatus.shortTokenCount(value))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var zoneDivider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 12)
            .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private func usageColor(percentage: Double) -> Color {
        let t = min(max(percentage / 100, 0), 1)
        let hue: Double
        if t < 0.6 {
            hue = 0.33 - (0.33 - 0.08) * (t / 0.6)
        } else {
            hue = 0.08 * (1 - (t - 0.6) / 0.4)
        }
        return Color(hue: hue, saturation: 0.75, brightness: 0.85)
    }

}
