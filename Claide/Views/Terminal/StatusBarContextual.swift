// ABOUTME: "Contextual Pulse" status bar — adapts display based on context usage state.
// ABOUTME: Minimal at low usage, shows warnings and actions as context fills up.

import SwiftUI

struct StatusBarContextual: View {
    let status: SessionStatus?
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"
    @State private var isHovering = false

    var body: some View {
        let _ = schemeName
        if let status {
            let state = contextState(percentage: status.usedPercentage)

            HStack(spacing: 8) {
                // State indicator
                stateIndicator(state: state)

                // Primary content changes based on state
                primaryContent(status: status, state: state)

                Spacer()

                // Secondary info (visible on hover or when state is elevated)
                if isHovering || state != .calm {
                    secondaryContent(status: status, state: state)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(statusBackground(state: state))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(stateAccentColor(state: state).opacity(0.4))
                    .frame(height: 1)
            }
            .animation(.easeInOut(duration: 0.3), value: state)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
        }
    }

    // MARK: - State Machine

    private enum ContextState: Equatable {
        case calm      // < 50% — minimal display
        case active    // 50-70% — normal display
        case warming   // 70-85% — yellow warning
        case critical  // > 85% — red alert
    }

    private func contextState(percentage: Double) -> ContextState {
        switch percentage {
        case ..<50: return .calm
        case ..<70: return .active
        case ..<85: return .warming
        default: return .critical
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func stateIndicator(state: ContextState) -> some View {
        Circle()
            .fill(stateAccentColor(state: state))
            .frame(width: 6, height: 6)
            .overlay {
                if state == .critical {
                    Circle()
                        .fill(stateAccentColor(state: state).opacity(0.4))
                        .frame(width: 10, height: 10)
                }
            }
    }

    @ViewBuilder
    private func primaryContent(status: SessionStatus, state: ContextState) -> some View {
        switch state {
        case .calm:
            // Just remaining tokens, very quiet
            HStack(spacing: 4) {
                Text(SessionStatus.shortTokenCount(status.remainingTokens))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                Text("remaining")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted.opacity(0.6))
            }

        case .active:
            // Remaining with label
            HStack(spacing: 4) {
                Text(SessionStatus.shortTokenCount(status.remainingTokens))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Text("remaining")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }

        case .warming:
            // Warning state — remaining in accent color
            HStack(spacing: 4) {
                Text(SessionStatus.shortTokenCount(status.remainingTokens))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(stateAccentColor(state: state))
                Text("remaining")
                    .font(.system(size: 10))
                    .foregroundStyle(stateAccentColor(state: state).opacity(0.7))
            }

        case .critical:
            // Alert state
            HStack(spacing: 4) {
                Text(SessionStatus.shortTokenCount(status.remainingTokens))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(stateAccentColor(state: state))
                Text("compaction soon")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(stateAccentColor(state: state).opacity(0.8))
            }
        }
    }

    @ViewBuilder
    private func secondaryContent(status: SessionStatus, state: ContextState) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text(status.modelDisplayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: 3) {
                Text("OUT")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                Text(SessionStatus.shortTokenCount(status.outputTokens))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - State-Dependent Styling

    private func stateAccentColor(state: ContextState) -> Color {
        switch state {
        case .calm:    return Palette.color(.uiBlue)
        case .active:  return Palette.color(.uiGreen)
        case .warming: return Palette.color(.uiYellow)
        case .critical: return Palette.color(.uiRed)
        }
    }

    private func statusBackground(state: ContextState) -> some ShapeStyle {
        Theme.backgroundSunken
    }

}
