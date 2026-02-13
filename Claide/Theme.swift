// ABOUTME: Centralized design tokens derived from the active terminal color scheme.
// ABOUTME: Chrome colors adapt to the scheme; semantic colors (status, priority) stay fixed.

import SwiftUI

enum Theme {
    // Terminal colors read from Ghostty's config so chrome matches the terminal.
    private static var schemeBG: NSColor { GhosttyApp.backgroundColor }
    private static var schemeFG: NSColor { GhosttyApp.foregroundColor }

    // Background layers (derived from terminal color scheme)
    static var backgroundPrimary: Color { Color(nsColor: schemeBG) }
    static var backgroundPanel: Color {
        Color(nsColor: schemeBG.blended(withFraction: 0.04, of: schemeFG) ?? schemeBG)
    }
    static var backgroundSunken: Color {
        Color(nsColor: schemeBG.blended(withFraction: 0.20, of: .black) ?? schemeBG)
    }
    static var backgroundHover: Color {
        Color(nsColor: schemeBG.blended(withFraction: 0.08, of: schemeFG) ?? schemeBG)
    }

    // Border
    static var border: Color {
        Color(nsColor: schemeBG.blended(withFraction: 0.1, of: schemeFG) ?? schemeFG)
    }

    // Text
    static var textPrimary: Color { Color(nsColor: schemeFG) }
    static var textSecondary: Color {
        Color(nsColor: schemeFG.blended(withFraction: 0.45, of: schemeBG) ?? schemeFG)
    }
    static var textMuted: Color {
        Color(nsColor: schemeFG.blended(withFraction: 0.65, of: schemeBG) ?? schemeFG)
    }

    // Status (fixed)
    static let statusOpen       = Palette.color(.uiBlue)
    static let statusInProgress = Palette.color(.uiYellow)
    static let statusBlocked    = Palette.color(.uiRed)
    static let statusClosed     = Palette.color(.uiGreen)

    // Priority (fixed)
    static let priorityCritical = Palette.color(.priCritical)
    static let priorityHigh     = Palette.color(.uiOrange)
    static let priorityMedium   = Palette.color(.priMedium)
    static let priorityLow      = Palette.color(.priLow)
    static let priorityBacklog  = Palette.color(.priBacklog)

    // Accent (fixed)
    static let accent   = Palette.color(.uiGreen)
    static let negative = Palette.color(.uiRed)

    // Type colors (fixed)
    static let typeBug     = Palette.color(.typeBug)
    static let typeTask    = Palette.color(.typeTask)
    static let typeEpic    = Palette.color(.typeEpic)
    static let typeFeature = Palette.color(.typeFeature)
    static let typeChore   = Palette.color(.typeChore)

    // Badge color sets (recomputed to track dynamic backgroundPanel)
    static var badgeBug:        BadgeColors { BadgeColors(base: typeBug) }
    static var badgeTask:       BadgeColors { BadgeColors(base: typeTask) }
    static var badgeEpic:       BadgeColors { BadgeColors(base: typeEpic) }
    static var badgeFeature:    BadgeColors { BadgeColors(base: typeFeature) }
    static var badgeChore:      BadgeColors { BadgeColors(base: typeChore) }
    static var badgeOpen:       BadgeColors { BadgeColors(base: statusOpen) }
    static var badgeInProgress: BadgeColors { BadgeColors(base: statusInProgress) }
    static var badgeClosed:     BadgeColors { BadgeColors(base: statusClosed) }
    static var badgeBlocked:    BadgeColors { BadgeColors(base: statusBlocked) }
    static var badgeCritical:   BadgeColors { BadgeColors(base: priorityCritical) }
    static var badgeHigh:       BadgeColors { BadgeColors(base: priorityHigh) }
    static var badgeMedium:     BadgeColors { BadgeColors(base: priorityMedium) }
    static var badgeLow:        BadgeColors { BadgeColors(base: priorityLow) }
    static var badgeBacklog:    BadgeColors { BadgeColors(base: priorityBacklog) }

    // Selection glow for graph highlighting (fixed)
    static let selectionGlow = Palette.color(.yellow)

    // Edge colors for graph
    static let edgeBlocks  = Palette.color(.uiRed).opacity(0.6)
    static var edgeDefault: Color {
        Color(nsColor: schemeFG.blended(withFraction: 0.7, of: schemeBG) ?? schemeFG)
    }

    // Typography — sizes derived from the user's "uiFontSize" preference.
    private static var baseFontSize: CGFloat {
        let size = UserDefaults.standard.double(forKey: "uiFontSize")
        return size > 0 ? size : 12
    }
    static var bodyFont: Font { .system(size: baseFontSize) }
    static var bodyFontSmall: Font { .system(size: baseFontSize - 2) }
    static var labelFont: Font { .system(size: baseFontSize - 2, weight: .medium) }
    static var headingFont: Font { .system(size: baseFontSize - 1, weight: .semibold) }
    static var titleFont: Font { .system(size: baseFontSize + 1, weight: .bold) }

    // Spacing
    static let panelPadding: CGFloat = 12
    static let panelCornerRadius: CGFloat = 2
    static let borderWidth: CGFloat = 1.0
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

/// Describes the visual style of a single tooltip line.
enum TooltipLineStyle {
    case bold       // Medium weight, primary color
    case normal     // Regular weight, primary color
    case muted      // Regular weight, dimmed color
    case mono       // Monospaced, slightly smaller
}

/// A single styled line in a structured tooltip.
struct TooltipLine {
    let text: String
    let style: TooltipLineStyle
}

/// Fast-appearing tooltip for SwiftUI views where `.help()` doesn't work
/// (e.g. buttons with `.buttonStyle(.plain)`).
/// Shows after 0.1s instead of the default ~1.5s macOS delay.
/// Supports plain text or structured multi-line content with accent color.
struct Tooltip: NSViewRepresentable {
    let lines: [TooltipLine]
    let accentColor: Color?

    /// Plain text tooltip
    init(_ text: String) {
        self.lines = [TooltipLine(text: text, style: .normal)]
        self.accentColor = nil
    }

    /// Structured tooltip with individually styled lines and optional accent
    init(lines: [TooltipLine], accentColor: Color? = nil) {
        self.lines = lines
        self.accentColor = accentColor
    }

    func makeNSView(context: Context) -> TooltipView {
        TooltipView(lines: lines, accentColor: accentColor.map { NSColor($0) })
    }

    func updateNSView(_ nsView: TooltipView, context: Context) {
        nsView.lines = lines
        nsView.accentColor = accentColor.map { NSColor($0) }
    }

    final class TooltipView: NSView {
        var lines: [TooltipLine]
        var accentColor: NSColor?
        private var hoverTimer: Timer?
        private var tooltipWindow: NSWindow?

        init(lines: [TooltipLine], accentColor: NSColor?) {
            self.lines = lines
            self.accentColor = accentColor
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

        // MARK: - Label Factory

        private func makeLabel(_ line: TooltipLine) -> NSTextField {
            let font: NSFont
            let color: NSColor

            switch line.style {
            case .bold:
                font = NSFont.systemFont(ofSize: 12, weight: .medium)
                color = NSColor(srgbRed: 224/255, green: 230/255, blue: 235/255, alpha: 1)
            case .normal:
                font = NSFont.systemFont(ofSize: 11)
                color = NSColor(srgbRed: 224/255, green: 230/255, blue: 235/255, alpha: 1)
            case .muted:
                font = NSFont.systemFont(ofSize: 10)
                color = NSColor(srgbRed: 89/255, green: 97/255, blue: 107/255, alpha: 1)
            case .mono:
                font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
                color = NSColor(srgbRed: 224/255, green: 230/255, blue: 235/255, alpha: 0.75)
            }

            let label: NSTextField
            if line.style == .mono {
                // Wrapping label for long file paths
                label = NSTextField(wrappingLabelWithString: line.text)
                label.maximumNumberOfLines = 3
            } else {
                label = NSTextField(labelWithString: line.text)
                label.lineBreakMode = .byTruncatingTail
                label.maximumNumberOfLines = 1
            }
            label.font = font
            label.textColor = color
            label.isSelectable = false
            return label
        }

        // MARK: - Show / Hide

        private func showTooltip() {
            guard let window, let screen = window.screen else { return }
            let mouseScreen = NSEvent.mouseLocation
            let paddingH: CGFloat = 12
            let paddingV: CGFloat = 10
            let maxTipWidth: CGFloat = 340
            let lineSpacing: CGFloat = 3
            let isStructured = accentColor != nil && lines.count >= 3
            let maxTextWidth = maxTipWidth - paddingH * 2

            // Create and measure labels (constrained to max width)
            var labelData: [(NSTextField, CGSize)] = []
            var maxWidth: CGFloat = 0
            for line in lines {
                let label = makeLabel(line)
                label.preferredMaxLayoutWidth = maxTextWidth
                let size = label.fittingSize
                let constrainedWidth = min(size.width, maxTextWidth)
                // Re-measure height at constrained width for wrapping labels
                let finalSize: CGSize
                if constrainedWidth < size.width {
                    label.preferredMaxLayoutWidth = constrainedWidth
                    finalSize = CGSize(width: constrainedWidth, height: label.fittingSize.height)
                } else {
                    finalSize = size
                }
                labelData.append((label, finalSize))
                maxWidth = max(maxWidth, finalSize.width)
            }

            // Calculate total content height
            let accentGap: CGFloat = 10   // 4 + 1.5 accent + 4.5
            let separatorGap: CGFloat = 12 // 5.5 + 0.5 sep + 6
            var contentHeight: CGFloat = 0
            for (i, (_, size)) in labelData.enumerated() {
                contentHeight += size.height
                if i < labelData.count - 1 {
                    if isStructured && i == 0 {
                        contentHeight += accentGap
                    } else if isStructured && i == labelData.count - 2 {
                        contentHeight += separatorGap
                    } else {
                        contentHeight += lineSpacing
                    }
                }
            }

            let tipWidth = maxWidth + paddingH * 2
            let tipHeight = contentHeight + paddingV * 2

            // Layout labels top-down (NSView y=0 is bottom)
            var y = tipHeight - paddingV
            var accentLineY: CGFloat = 0
            var separatorY: CGFloat = 0

            for (i, (label, size)) in labelData.enumerated() {
                y -= size.height
                label.frame = NSRect(x: paddingH, y: y, width: maxWidth, height: size.height)

                if i < labelData.count - 1 {
                    if isStructured && i == 0 {
                        y -= 4
                        y -= 1.5
                        accentLineY = y
                        y -= 4.5
                    } else if isStructured && i == labelData.count - 2 {
                        y -= 5.5
                        y -= 0.5
                        separatorY = y
                        y -= 6
                    } else {
                        y -= lineSpacing
                    }
                }
            }

            // Position window near cursor
            var origin = CGPoint(x: mouseScreen.x + 12, y: mouseScreen.y - tipHeight - 8)
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

            // Container with rounded corners
            let container = NSView(frame: NSRect(origin: .zero, size: CGSize(width: tipWidth, height: tipHeight)))
            container.wantsLayer = true
            container.layer?.cornerRadius = 10
            container.layer?.masksToBounds = true

            // Gradient background: lighter at top, darker at bottom
            let gradient = CAGradientLayer()
            gradient.frame = container.bounds
            gradient.colors = [
                CGColor(srgbRed: 22/255, green: 25/255, blue: 33/255, alpha: 1),
                CGColor(srgbRed: 13/255, green: 15/255, blue: 20/255, alpha: 1),
            ]
            gradient.startPoint = CGPoint(x: 0.5, y: 1) // top
            gradient.endPoint = CGPoint(x: 0.5, y: 0)   // bottom
            container.layer?.addSublayer(gradient)

            // Accent underline after header
            if isStructured, let color = accentColor {
                let accent = CALayer()
                accent.frame = CGRect(x: paddingH, y: accentLineY, width: maxWidth, height: 1.5)
                accent.backgroundColor = color.withAlphaComponent(0.5).cgColor
                accent.cornerRadius = 0.75
                container.layer?.addSublayer(accent)
            }

            // Separator before path
            if isStructured {
                let sep = CALayer()
                sep.frame = CGRect(x: paddingH, y: separatorY, width: maxWidth, height: 0.5)
                sep.backgroundColor = CGColor(srgbRed: 46/255, green: 51/255, blue: 61/255, alpha: 1)
                container.layer?.addSublayer(sep)
            }

            // Add labels on top
            for (label, _) in labelData {
                container.addSubview(label)
            }

            tipWindow.contentView = container
            tipWindow.hasShadow = true

            // Fade-in animation
            tipWindow.alphaValue = 0
            tipWindow.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                tipWindow.animator().alphaValue = 1
            }

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
    @AppStorage("terminalColorScheme") private var schemeName: String = "hexed"
    @ViewBuilder let content: () -> Content

    var body: some View {
        let _ = schemeName
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
