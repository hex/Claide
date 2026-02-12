// ABOUTME: Context menu for terminal tabs with rename, color, and close operations.
// ABOUTME: Applied as a ViewModifier that merges with existing tab actions.

import SwiftUI

extension View {
    func terminalTabContextMenu(
        tabId: UUID,
        tabCount: Int,
        isLastTab: Bool,
        tabColor: TabColor?,
        onRename: @escaping () -> Void,
        onSetColor: @escaping (TabColor?) -> Void,
        onClose: @escaping () -> Void,
        onCloseOthers: @escaping () -> Void,
        onCloseToRight: @escaping () -> Void,
        onCloseAll: @escaping () -> Void
    ) -> some View {
        modifier(TerminalTabContextMenu(
            tabId: tabId,
            tabCount: tabCount,
            isLastTab: isLastTab,
            tabColor: tabColor,
            onRename: onRename,
            onSetColor: onSetColor,
            onClose: onClose,
            onCloseOthers: onCloseOthers,
            onCloseToRight: onCloseToRight,
            onCloseAll: onCloseAll
        ))
    }
}

private struct TerminalTabContextMenu: ViewModifier {
    let tabId: UUID
    let tabCount: Int
    let isLastTab: Bool
    let tabColor: TabColor?
    let onRename: () -> Void
    let onSetColor: (TabColor?) -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseToRight: () -> Void
    let onCloseAll: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Rename...") { onRename() }

            Menu("Tab Color") {
                ForEach(TabColor.allCases, id: \.self) { preset in
                    Toggle(isOn: Binding(
                        get: { tabColor == preset },
                        set: { _ in onSetColor(preset) }
                    )) {
                        Label {
                            Text(preset.label)
                        } icon: {
                            preset.swatch
                        }
                    }
                }

                Divider()

                Button("Clear") { onSetColor(nil) }
                    .disabled(tabColor == nil)
            }

            Divider()

            Button("Close Tab") { onClose() }

            Button("Close Other Tabs") { onCloseOthers() }
                .disabled(tabCount <= 1)

            Button("Close Tabs to the Right") { onCloseToRight() }
                .disabled(isLastTab)

            Button("Close All Tabs") { onCloseAll() }
        }
    }
}
