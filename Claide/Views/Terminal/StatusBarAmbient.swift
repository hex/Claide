// ABOUTME: "Ambient Fill" status bar — the bar background IS the progress indicator.
// ABOUTME: Minimal text floats over a translucent gradient that fills left-to-right with usage.

import SwiftUI

struct StatusBarAmbient: View {
    let status: SessionStatus?
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"

    var body: some View {
        let _ = schemeName
        if let status {
            HStack(spacing: 0) {
                // Left: percentage as the primary metric
                Text("\(Int(status.usedPercentage))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))

                Text(" context")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()

                // Right: compact token count
                Text(shortTokenCount(status.totalInputTokens))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Text(" / ")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
                Text(shortTokenCount(status.contextWindowSize))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                ambientFill(percentage: status.usedPercentage)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: Theme.borderWidth)
            }
        }
    }

    /// The bar background: a gradient that fills from left to right based on usage.
    /// Low usage = subtle cool blue glow. High usage = warm red/orange glow.
    @ViewBuilder
    private func ambientFill(percentage: Double) -> some View {
        let fraction = min(max(percentage / 100, 0), 1)

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Base: dark background
                Theme.backgroundSunken

                // Filled portion: translucent gradient
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors(fraction: fraction),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * fraction)
                    .opacity(0.3)

                // Soft glow at the leading edge of the fill
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                fillColor(fraction: fraction).opacity(0.15),
                                .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * min(fraction + 0.05, 1))
            }
        }
    }

    private func gradientColors(fraction: Double) -> [Color] {
        if fraction < 0.5 {
            // Cool blue -> blue-purple
            return [
                Color(red: 0.34, green: 0.55, blue: 1.0),   // #578cf7 - Tokyo Night blue
                Color(red: 0.45, green: 0.45, blue: 0.95),   // blue-purple
            ]
        } else if fraction < 0.75 {
            // Blue-purple -> amber
            return [
                Color(red: 0.45, green: 0.45, blue: 0.95),
                Color(red: 0.95, green: 0.6, blue: 0.2),     // amber
            ]
        } else {
            // Amber -> red
            return [
                Color(red: 0.95, green: 0.6, blue: 0.2),
                Color(red: 0.9, green: 0.3, blue: 0.3),      // red
            ]
        }
    }

    private func fillColor(fraction: Double) -> Color {
        if fraction < 0.5 {
            return Color(red: 0.34, green: 0.55, blue: 1.0)
        } else if fraction < 0.75 {
            return Color(red: 0.95, green: 0.6, blue: 0.2)
        } else {
            return Color(red: 0.9, green: 0.3, blue: 0.3)
        }
    }

    private func shortTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000)k"
        }
        return "\(count)"
    }
}
