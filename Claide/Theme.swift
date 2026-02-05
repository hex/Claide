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

    // Typography — sizes derived from the user's "uiFontSize" preference.
    private static var baseFontSize: CGFloat {
        let size = UserDefaults.standard.double(forKey: "uiFontSize")
        return size > 0 ? size : 13
    }
    static var bodyFont: Font { .system(size: baseFontSize) }
    static var bodyFontSmall: Font { .system(size: baseFontSize - 2) }
    static var labelFont: Font { .system(size: baseFontSize - 2, weight: .medium) }
    static var headingFont: Font { .system(size: baseFontSize - 1, weight: .semibold) }
    static var titleFont: Font { .system(size: baseFontSize + 1, weight: .bold) }

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

/// Fast-appearing tooltip for SwiftUI views where `.help()` doesn't work
/// (e.g. buttons with `.buttonStyle(.plain)`).
/// Shows after 0.1s instead of the default ~1.5s macOS delay.
struct Tooltip: NSViewRepresentable {
    let text: String

    init(_ text: String) { self.text = text }

    func makeNSView(context: Context) -> TooltipView {
        TooltipView(text: text)
    }

    func updateNSView(_ nsView: TooltipView, context: Context) {
        nsView.tooltipText = text
    }

    final class TooltipView: NSView {
        var tooltipText: String
        private var hoverTimer: Timer?
        private var tooltipWindow: NSWindow?

        init(text: String) {
            self.tooltipText = text
            super.init(frame: .zero)
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func mouseEntered(with event: NSEvent) {
            hoverTimer?.invalidate()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.showTooltip()
            }
        }

        override func mouseExited(with event: NSEvent) {
            hoverTimer?.invalidate()
            hoverTimer = nil
            hideTooltip()
        }

        override func removeFromSuperview() {
            hoverTimer?.invalidate()
            hideTooltip()
            super.removeFromSuperview()
        }

        private func showTooltip() {
            guard let window, let screen = window.screen else { return }
            let mouseScreen = NSEvent.mouseLocation
            let padding: CGFloat = 4
            let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let size = (tooltipText as NSString).size(withAttributes: attrs)
            let tipWidth = size.width + padding * 2 + 4
            let tipHeight = size.height + padding * 2

            var origin = CGPoint(x: mouseScreen.x + 12, y: mouseScreen.y - tipHeight - 8)
            // Keep on screen
            if origin.x + tipWidth > screen.visibleFrame.maxX {
                origin.x = screen.visibleFrame.maxX - tipWidth
            }
            if origin.y < screen.visibleFrame.minY {
                origin.y = mouseScreen.y + 16
            }

            let tipWindow = NSWindow(
                contentRect: NSRect(origin: origin, size: CGSize(width: tipWidth, height: tipHeight)),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            tipWindow.isOpaque = false
            tipWindow.backgroundColor = .clear
            tipWindow.level = .floating
            tipWindow.ignoresMouseEvents = true

            let label = NSTextField(labelWithString: tooltipText)
            label.font = font
            label.textColor = .white
            label.frame = NSRect(x: padding, y: padding, width: size.width + 4, height: size.height)

            let container = NSView(frame: NSRect(origin: .zero, size: CGSize(width: tipWidth, height: tipHeight)))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
            container.layer?.cornerRadius = 4
            container.layer?.borderWidth = 0.5
            container.layer?.borderColor = NSColor(white: 0.3, alpha: 1).cgColor
            container.addSubview(label)

            tipWindow.contentView = container
            tipWindow.orderFront(nil)
            self.tooltipWindow = tipWindow
        }

        private func hideTooltip() {
            tooltipWindow?.orderOut(nil)
            tooltipWindow = nil
        }
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
                    .font(Theme.bodyFontSmall)
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
