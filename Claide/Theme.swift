// ABOUTME: Centralized design tokens for the dark terminal-inspired UI.
// ABOUTME: Colors, fonts, and spacing constants used across all views.

import SwiftUI

enum Theme {
    // Background layers (darkest to lightest)
    static let backgroundPrimary = Palette.color(.bgPrimary)
    static let backgroundPanel   = Palette.color(.bgPanel)
    static let backgroundSunken  = Palette.color(.bgSunken)
    static let backgroundHover   = Palette.color(.bgHover)

    // Border
    static let border = Palette.color(.border)

    // Text
    static let textPrimary   = Palette.color(.fgPrimary)
    static let textSecondary = Palette.color(.fgSecondary)
    static let textMuted     = Palette.color(.fgMuted)

    // Status
    static let statusOpen       = Palette.color(.uiBlue)
    static let statusInProgress = Palette.color(.uiYellow)
    static let statusBlocked    = Palette.color(.uiRed)
    static let statusClosed     = Palette.color(.uiGreen)

    // Priority (P0-P4)
    static let priorityCritical = Palette.color(.priCritical)
    static let priorityHigh     = Palette.color(.uiOrange)
    static let priorityMedium   = Palette.color(.priMedium)
    static let priorityLow      = Palette.color(.priLow)
    static let priorityBacklog  = Palette.color(.priBacklog)

    // Accent
    static let accent   = Palette.color(.uiGreen)
    static let negative = Palette.color(.uiRed)

    // Type colors (base colors for node fill at low zoom and badge derivation)
    static let typeBug     = Palette.color(.typeBug)
    static let typeTask    = Palette.color(.typeTask)
    static let typeEpic    = Palette.color(.typeEpic)
    static let typeFeature = Palette.color(.typeFeature)
    static let typeChore   = Palette.color(.typeChore)

    // Pre-computed badge color sets
    static let badgeBug        = BadgeColors(base: typeBug)
    static let badgeTask       = BadgeColors(base: typeTask)
    static let badgeEpic       = BadgeColors(base: typeEpic)
    static let badgeFeature    = BadgeColors(base: typeFeature)
    static let badgeChore      = BadgeColors(base: typeChore)
    static let badgeOpen       = BadgeColors(base: statusOpen)
    static let badgeInProgress = BadgeColors(base: statusInProgress)
    static let badgeClosed     = BadgeColors(base: statusClosed)
    static let badgeBlocked    = BadgeColors(base: statusBlocked)
    static let badgeCritical   = BadgeColors(base: priorityCritical)
    static let badgeHigh       = BadgeColors(base: priorityHigh)
    static let badgeMedium     = BadgeColors(base: priorityMedium)
    static let badgeLow        = BadgeColors(base: priorityLow)
    static let badgeBacklog    = BadgeColors(base: priorityBacklog)

    // Selection glow for graph highlighting
    static let selectionGlow = Palette.color(.yellow)

    // Edge colors for graph
    static let edgeBlocks  = Palette.color(.uiRed).opacity(0.6)
    static let edgeDefault = Palette.color(.edgeMuted)

    // Typography
    static let monoFont = Font.system(size: 12, design: .monospaced)
    static let monoFontSmall = Font.system(size: 10, design: .monospaced)
    static let labelFont = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let headingFont = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let titleFont = Font.system(size: 13, weight: .bold, design: .monospaced)

    // Spacing
    static let panelPadding: CGFloat = 12
    static let panelCornerRadius: CGFloat = 2
    static let borderWidth: CGFloat = 0.5
}

/// Pill badge color triplet derived from a base color using beads-ui blend formula.
/// bg = 80% backgroundPanel + 20% base, fg = 75% base + 25% white, border = fg at 35% opacity
struct BadgeColors: Equatable, Sendable {
    let bg: Color
    let fg: Color
    let border: Color

    init(base: Color) {
        let resolved = NSColor(base).usingColorSpace(.sRGB) ?? NSColor(base)
        let br = NSColor(Theme.backgroundPanel).usingColorSpace(.sRGB) ?? NSColor(Theme.backgroundPanel)

        let baseR = resolved.redComponent
        let baseG = resolved.greenComponent
        let baseB = resolved.blueComponent

        let panelR = br.redComponent
        let panelG = br.greenComponent
        let panelB = br.blueComponent

        // bg = 80% panel + 20% base
        bg = Color(
            red: panelR * 0.8 + baseR * 0.2,
            green: panelG * 0.8 + baseG * 0.2,
            blue: panelB * 0.8 + baseB * 0.2
        )

        // fg = 75% base + 25% white
        fg = Color(
            red: baseR * 0.75 + 0.25,
            green: baseG * 0.75 + 0.25,
            blue: baseB * 0.75 + 0.25
        )

        // border = fg at 35% opacity
        border = Color(
            red: baseR * 0.75 + 0.25,
            green: baseG * 0.75 + 0.25,
            blue: baseB * 0.75 + 0.25
        ).opacity(0.35)
    }
}

/// Section header styled like the Mahoraga dashboard: uppercase, letter-spaced, muted
struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.labelFont)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.5)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.monoFontSmall)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.bottom, 4)
    }
}

/// Panel container with thin border, dark background
struct PanelView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(Theme.panelPadding)
        .background(Theme.backgroundPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelCornerRadius)
                .stroke(Theme.border, lineWidth: Theme.borderWidth)
        )
    }
}
