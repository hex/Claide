// ABOUTME: NSSplitViewController that manages the terminal and sidebar panes.
// ABOUTME: Sidebar pane is collapsible with animated toggle via Cmd+B.

import AppKit
import SwiftUI

@MainActor
final class MainSplitViewController: NSSplitViewController {

    private let tabManager: TerminalTabManager

    init(tabManager: TerminalTabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)

        let terminalHost = NSHostingController(
            rootView: TerminalSection(tabManager: tabManager)
        )
        terminalHost.sizingOptions = []
        let terminalItem = NSSplitViewItem(viewController: terminalHost)
        terminalItem.minimumThickness = 400
        terminalItem.holdingPriority = .defaultLow

        let sidebarHost = NSHostingController(
            rootView: SidebarSection(tabManager: tabManager)
        )
        sidebarHost.sizingOptions = []
        let sidebarItem = NSSplitViewItem(viewController: sidebarHost)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 200
        sidebarItem.holdingPriority = .defaultLow + 1

        addSplitViewItem(terminalItem)
        addSplitViewItem(sidebarItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = true
        splitView.dividerStyle = .thin
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        setInitialDividerPosition()
        restoreSidebarState()
    }

    // MARK: - Sidebar Toggle

    func toggleSidebarPanel() {
        guard splitViewItems.count > 1 else { return }
        let sidebarItem = splitViewItems[1]

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sidebarItem.animator().isCollapsed.toggle()
        } completionHandler: {
            DispatchQueue.main.async { [weak self] in
                self?.saveSidebarState()
            }
        }
    }

    var isSidebarCollapsed: Bool {
        guard splitViewItems.count > 1 else { return true }
        return splitViewItems[1].isCollapsed
    }

    // MARK: - Divider Position

    private func setInitialDividerPosition() {
        guard let window = view.window else { return }
        let savedFraction = UserDefaults.standard.double(forKey: "sidebarDividerFraction")
        let fraction = savedFraction > 0 ? savedFraction : 0.7
        let position = window.frame.width * fraction
        splitView.setPosition(position, ofDividerAt: 0)
    }

    // MARK: - Persistence

    private func saveSidebarState() {
        guard splitViewItems.count > 1 else { return }
        UserDefaults.standard.set(splitViewItems[1].isCollapsed, forKey: "sidebarCollapsed")
    }

    private func restoreSidebarState() {
        let collapsed = UserDefaults.standard.bool(forKey: "sidebarCollapsed")
        guard splitViewItems.count > 1, collapsed else { return }
        // Collapse without animation on launch
        splitViewItems[1].isCollapsed = true
    }

    // MARK: - NSSplitViewDelegate

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard splitViewItems.count > 1, !splitViewItems[1].isCollapsed else { return }
        let total = splitView.bounds.width
        guard total > 0 else { return }
        let position = splitView.subviews[0].frame.width
        UserDefaults.standard.set(position / total, forKey: "sidebarDividerFraction")
    }
}
