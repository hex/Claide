// ABOUTME: Floating search bar for find-in-buffer (Cmd+F).
// ABOUTME: Contains a text field and prev/next buttons, dispatching via closures.

import AppKit

/// Compact search bar overlay for terminal find-in-buffer.
final class TerminalSearchBar: NSView {

    let searchField = NSTextField()

    /// Called when the search query changes (including empty string to clear).
    var onQuery: ((String) -> Void)?
    /// Called when the user presses Enter or clicks the next button.
    var onNext: (() -> Void)?
    /// Called when the user presses Shift+Enter or clicks the previous button.
    var onPrevious: (() -> Void)?
    /// Called when the user presses Escape.
    var onDismiss: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    /// Reset the search field text.
    func clear() {
        searchField.stringValue = ""
    }

    // MARK: - Setup

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.95).cgColor
        layer?.cornerRadius = 6
        layer?.borderColor = NSColor(white: 0.3, alpha: 1).cgColor
        layer?.borderWidth = 1

        searchField.placeholderString = "Find"
        searchField.isBordered = false
        searchField.focusRingType = .none
        searchField.drawsBackground = false
        searchField.textColor = .white
        searchField.font = .systemFont(ofSize: 13)
        searchField.cell?.sendsActionOnEndEditing = false
        searchField.target = self
        searchField.action = #selector(searchFieldAction)
        searchField.delegate = self
        addSubview(searchField)

        let prevButton = makeButton(symbol: "chevron.up", action: #selector(prevClicked))
        let nextButton = makeButton(symbol: "chevron.down", action: #selector(nextClicked))
        addSubview(prevButton)
        addSubview(nextButton)

        // Layout: [field][prev][next]
        searchField.translatesAutoresizingMaskIntoConstraints = false
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: prevButton.leadingAnchor, constant: -4),

            prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 24),
            prevButton.heightAnchor.constraint(equalToConstant: 24),

            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 24),
            nextButton.heightAnchor.constraint(equalToConstant: 24),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    private func makeButton(symbol: String, action: Selector) -> NSButton {
        let button: NSButton
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button = NSButton(image: image, target: self, action: action)
        } else {
            button = NSButton(title: symbol == "chevron.up" ? "^" : "v", target: self, action: action)
        }
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .lightGray
        return button
    }

    // MARK: - Actions

    @objc private func searchFieldAction() {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .shift {
            onPrevious?()
        } else {
            onNext?()
        }
    }

    @objc private func prevClicked() {
        onPrevious?()
    }

    @objc private func nextClicked() {
        onNext?()
    }

    // MARK: - Key Handling

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}

// MARK: - NSTextFieldDelegate

extension TerminalSearchBar: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        onQuery?(searchField.stringValue)
    }
}
