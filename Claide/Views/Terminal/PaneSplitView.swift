// ABOUTME: NSSplitView subclass for terminal pane layouts.
// ABOUTME: Enforces minimum pane sizes and prevents pane collapse by dragging.

import AppKit

final class PaneSplitView: NSSplitView, NSSplitViewDelegate {

    /// Minimum dimension (width or height) for any child pane.
    static let minimumPaneDimension: CGFloat = 50

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private var needsEqualDividers = true

    private func commonInit() {
        delegate = self
        dividerStyle = .thin
    }

    /// Equalize the divider position once after the split view gets a real frame.
    /// Called from the delegate's resizeSubviews callback on the first non-zero layout.
    func equalizeIfNeeded() {
        guard needsEqualDividers, arrangedSubviews.count >= 2 else { return }
        let dimension = isVertical ? bounds.width : bounds.height
        guard dimension > 0 else { return }
        needsEqualDividers = false
        setPosition(dimension / 2, ofDividerAt: 0)
    }

    // MARK: - NSSplitViewDelegate

    func splitView(
        _ splitView: NSSplitView,
        resizeSubviewsWithOldSize oldSize: NSSize
    ) {
        // Let the default behavior run first
        splitView.adjustSubviews()
        // Then equalize on first real layout
        equalizeIfNeeded()
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        proposedMinimumPosition + Self.minimumPaneDimension
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        proposedMaximumPosition - Self.minimumPaneDimension
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }
}
