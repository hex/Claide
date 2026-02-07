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

    private func commonInit() {
        delegate = self
        dividerStyle = .thin
    }

    // MARK: - NSSplitViewDelegate

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
