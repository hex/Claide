// ABOUTME: Manages an NSSplitView hierarchy that mirrors a PaneNode tree.
// ABOUTME: Rebuilds the view hierarchy on tree changes, preserving terminal view instances.

import AppKit

final class PaneContainerView: NSView {

    /// Called when a pane's close button is clicked.
    var onClosePane: ((PaneID) -> Void)?

    /// Current pane-to-view mapping, populated during applyTree.
    private var paneViews: [PaneID: NSView] = [:]

    /// Title bars keyed by pane ID, for dynamic title updates.
    private var titleBars: [PaneID: PaneTitleBar] = [:]

    /// Rebuild the view hierarchy to match the given pane tree.
    ///
    /// The `viewProvider` closure supplies the NSView for each terminal pane ID.
    /// Views are detached (not destroyed) before rebuilding, so MetalTerminalView
    /// instances survive across tree changes.
    func applyTree(_ tree: PaneNode, viewProvider: (PaneID) -> NSView?) {
        let preservedTitles = titleBars.mapValues { $0.title }
        subviews.forEach { $0.removeFromSuperview() }
        paneViews.removeAll()
        titleBars.removeAll()

        let showTitleBar = tree.paneCount > 1
        let root = buildView(for: tree, viewProvider: viewProvider, showTitleBar: showTitleBar)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for (id, title) in preservedTitles {
            titleBars[id]?.title = title
        }
    }

    /// Look up the view for a given pane ID.
    func paneView(for id: PaneID) -> NSView? {
        paneViews[id]
    }

    /// Update the title displayed in a pane's title bar.
    func setTitle(_ title: String, for paneID: PaneID) {
        titleBars[paneID]?.title = title
    }

    /// Highlight the active pane's title bar and dim others.
    func setActivePaneID(_ id: PaneID) {
        for (paneID, titleBar) in titleBars {
            titleBar.isActive = (paneID == id)
        }
    }

    /// Update a pane title bar's colors to match a terminal color scheme.
    func applyColorScheme(_ scheme: TerminalColorScheme, for paneID: PaneID) {
        titleBars[paneID]?.applyColorScheme(scheme)
    }

    // MARK: - Private

    private func buildView(
        for node: PaneNode,
        viewProvider: (PaneID) -> NSView?,
        showTitleBar: Bool
    ) -> NSView {
        switch node {
        case .terminal(let id):
            if let view = viewProvider(id) {
                paneViews[id] = view

                guard showTitleBar else {
                    view.translatesAutoresizingMaskIntoConstraints = true
                    return view
                }

                let titleBar = PaneTitleBar(paneID: id) { [weak self] id in
                    self?.onClosePane?(id)
                }
                titleBars[id] = titleBar

                let wrapper = NSView()
                wrapper.translatesAutoresizingMaskIntoConstraints = true

                titleBar.translatesAutoresizingMaskIntoConstraints = false
                view.translatesAutoresizingMaskIntoConstraints = false
                wrapper.addSubview(titleBar)
                wrapper.addSubview(view)

                NSLayoutConstraint.activate([
                    titleBar.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                    titleBar.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                    titleBar.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    titleBar.heightAnchor.constraint(equalToConstant: PaneTitleBar.height),

                    view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                    view.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
                    view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                ])

                return wrapper
            }
            return NSView()

        case .split(let axis, let children):
            let split = PaneSplitView()
            // horizontal axis = side-by-side panes = vertical divider
            split.isVertical = (axis == .horizontal)

            for child in children {
                let childView = buildView(for: child, viewProvider: viewProvider, showTitleBar: showTitleBar)
                split.addArrangedSubview(childView)
            }

            return split
        }
    }
}

// MARK: - Pane Title Bar

final class PaneTitleBar: NSView {

    static let height: CGFloat = 22

    var title: String = "" {
        didSet { titleField.stringValue = title }
    }

    var isActive: Bool = false {
        didSet { updateActiveAppearance() }
    }

    private let titleField: NSTextField
    private let closeButton: NSButton
    private let accentStripe = NSView()
    private let borderView = NSView()
    private var foregroundColor: NSColor = NSColor(Theme.textMuted)
    private let paneID: PaneID
    private let onClose: (PaneID) -> Void

    init(paneID: PaneID, onClose: @escaping (PaneID) -> Void) {
        self.paneID = paneID
        self.onClose = onClose
        self.titleField = NSTextField(labelWithString: "")
        self.closeButton = NSButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        super.init(frame: .zero)

        wantsLayer = true

        setupCloseButton()
        setupTitleField()
        setupBorder()

        let schemeName = UserDefaults.standard.string(forKey: "terminalColorScheme") ?? "hexed"
        applyColorScheme(TerminalColorScheme.named(schemeName))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close pane")
        closeButton.symbolConfiguration = .init(pointSize: 8, weight: .bold)
        closeButton.contentTintColor = .white.withAlphaComponent(0.35)
        closeButton.setButtonType(.momentaryChange)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Hover tracking
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 8
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        closeButton.addTrackingArea(area)
    }

    private func setupTitleField() {
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.font = .systemFont(ofSize: 10, weight: .medium)
        titleField.textColor = NSColor(Theme.textMuted)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.cell?.truncatesLastVisibleLine = true
        addSubview(titleField)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func setupBorder() {
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.wantsLayer = true
        borderView.layer?.backgroundColor = NSColor(Theme.border).cgColor
        addSubview(borderView)

        accentStripe.translatesAutoresizingMaskIntoConstraints = false
        accentStripe.wantsLayer = true
        accentStripe.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        accentStripe.isHidden = true
        addSubview(accentStripe)

        NSLayoutConstraint.activate([
            borderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            borderView.bottomAnchor.constraint(equalTo: bottomAnchor),
            borderView.heightAnchor.constraint(equalToConstant: Theme.borderWidth),

            accentStripe.leadingAnchor.constraint(equalTo: leadingAnchor),
            accentStripe.trailingAnchor.constraint(equalTo: trailingAnchor),
            accentStripe.topAnchor.constraint(equalTo: topAnchor),
            accentStripe.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    func applyColorScheme(_ scheme: TerminalColorScheme) {
        let bg = Palette.nsColor(scheme.background)
        layer?.backgroundColor = bg.blended(withFraction: 0.15, of: .black)?.cgColor ?? bg.cgColor
        foregroundColor = Palette.nsColor(scheme.foreground)
        closeButton.contentTintColor = foregroundColor.withAlphaComponent(0.35)
        borderView.layer?.backgroundColor = foregroundColor.withAlphaComponent(0.12).cgColor
        updateActiveAppearance()
    }

    private func updateActiveAppearance() {
        let showIndicator = UserDefaults.standard.bool(forKey: "paneFocusIndicator")
        accentStripe.isHidden = !isActive || !showIndicator
        titleField.textColor = foregroundColor.withAlphaComponent(isActive ? 1.0 : 0.5)
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.contentTintColor = foregroundColor.withAlphaComponent(0.9)
        closeButton.layer?.backgroundColor = foregroundColor.withAlphaComponent(0.15).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.contentTintColor = foregroundColor.withAlphaComponent(0.35)
        closeButton.layer?.backgroundColor = nil
    }

    @objc private func closeTapped() {
        onClose(paneID)
    }
}
