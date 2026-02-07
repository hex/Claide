// ABOUTME: Manages an NSSplitView hierarchy that mirrors a PaneNode tree.
// ABOUTME: Rebuilds the view hierarchy on tree changes, preserving terminal view instances.

import AppKit

final class PaneContainerView: NSView {

    /// Called when a pane's close button is clicked.
    var onClosePane: ((PaneID) -> Void)?

    /// Current pane-to-view mapping, populated during applyTree.
    private var paneViews: [PaneID: NSView] = [:]

    /// Rebuild the view hierarchy to match the given pane tree.
    ///
    /// The `viewProvider` closure supplies the NSView for each terminal pane ID.
    /// Views are detached (not destroyed) before rebuilding, so MetalTerminalView
    /// instances survive across tree changes.
    func applyTree(_ tree: PaneNode, viewProvider: (PaneID) -> NSView?) {
        subviews.forEach { $0.removeFromSuperview() }
        paneViews.removeAll()

        let showClose = tree.paneCount > 1
        let root = buildView(for: tree, viewProvider: viewProvider, showClose: showClose)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Look up the view for a given pane ID.
    func paneView(for id: PaneID) -> NSView? {
        paneViews[id]
    }

    // MARK: - Private

    private func buildView(
        for node: PaneNode,
        viewProvider: (PaneID) -> NSView?,
        showClose: Bool
    ) -> NSView {
        switch node {
        case .terminal(let id):
            if let view = viewProvider(id) {
                paneViews[id] = view

                guard showClose else {
                    view.translatesAutoresizingMaskIntoConstraints = true
                    return view
                }

                // Wrap in a container with a close button overlay
                let wrapper = NSView()
                wrapper.translatesAutoresizingMaskIntoConstraints = true

                view.translatesAutoresizingMaskIntoConstraints = false
                wrapper.addSubview(view)

                let button = PaneCloseButton(paneID: id) { [weak self] id in
                    self?.onClosePane?(id)
                }
                button.translatesAutoresizingMaskIntoConstraints = false
                wrapper.addSubview(button)

                NSLayoutConstraint.activate([
                    view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                    view.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),

                    button.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
                    button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -4),
                ])

                return wrapper
            }
            return NSView()

        case .split(let axis, let children):
            let split = PaneSplitView()
            // horizontal axis = side-by-side panes = vertical divider
            split.isVertical = (axis == .horizontal)

            for child in children {
                let childView = buildView(for: child, viewProvider: viewProvider, showClose: showClose)
                split.addArrangedSubview(childView)
            }

            return split
        }
    }
}

// MARK: - Close Button

private final class PaneCloseButton: NSButton {

    private let paneID: PaneID
    private let onClose: (PaneID) -> Void

    init(paneID: PaneID, onClose: @escaping (PaneID) -> Void) {
        self.paneID = paneID
        self.onClose = onClose
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))

        isBordered = false
        image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close pane")
        symbolConfiguration = .init(pointSize: 8, weight: .bold)
        contentTintColor = .white.withAlphaComponent(0.4)
        setButtonType(.momentaryChange)
        target = self
        action = #selector(closeTapped)

        wantsLayer = true
        layer?.cornerRadius = 8
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        contentTintColor = .white.withAlphaComponent(0.9)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        contentTintColor = .white.withAlphaComponent(0.4)
        layer?.backgroundColor = nil
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    @objc private func closeTapped() {
        onClose(paneID)
    }
}
