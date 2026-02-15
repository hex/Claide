// ABOUTME: Full-window overlay that displays the command palette search field and results list.
// ABOUTME: Handles keyboard navigation (arrows, enter, escape) and click-to-dismiss backdrop.

import SwiftUI

struct CommandPaletteOverlayView: View {
    @Bindable var manager: CommandPaletteManager
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { manager.dismiss() }

            VStack(spacing: 0) {
                searchField
                Divider()
                resultsList
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .tertiaryLabelColor).opacity(0.75))
            )
            .shadow(radius: 32, x: 0, y: 12)
            .frame(maxWidth: 500)
            .padding(.top, 100)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Resign AppKit first responder (e.g. GhosttyTerminalView) first,
            // then request SwiftUI focus after a frame so the TextField is
            // in the view hierarchy and ready to accept focus.
            NSApp.keyWindow?.makeFirstResponder(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                isSearchFocused = true
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        ZStack {
            // Hidden buttons for keyboard navigation.
            // The TextField's onMoveCommand / onExitCommand / onSubmit
            // are unreliable in overlays; hidden keyboard-shortcut buttons
            // work consistently.
            Group {
                Button { manager.moveSelection(.up) } label: { Color.clear }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.upArrow, modifiers: [])

                Button { manager.moveSelection(.down) } label: { Color.clear }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.downArrow, modifiers: [])

                Button { manager.activateSelected() } label: { Color.clear }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])

                Button { manager.dismiss() } label: { Color.clear }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Type a command...", text: $manager.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)
            }
            .padding(12)
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(manager.filteredItems.enumerated()), id: \.element.id) { index, item in
                        CommandPaletteRowView(item: item, isSelected: index == manager.selectedIndex)
                            .id(item.id)
                            .onTapGesture {
                                manager.selectedIndex = index
                                manager.activateSelected()
                            }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 300)
            .onChange(of: manager.selectedIndex) { _, newIndex in
                guard manager.filteredItems.indices.contains(newIndex) else { return }
                proxy.scrollTo(manager.filteredItems[newIndex].id, anchor: .center)
            }
        }
    }
}
