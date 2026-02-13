// ABOUTME: Searchable, grouped theme browser for the Appearance settings tab.
// ABOUTME: Replaces the flat dropdown with an inline scrollable list showing color swatches.

import SwiftUI

struct ThemeBrowser: View {
    @Binding var selection: String
    @State private var search = ""
    @State private var hoveredID: String?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        hexedRow
                        Divider().padding(.vertical, 4)
                        themeSection(title: "DARK", themes: filteredDark)
                        if !filteredDark.isEmpty && !filteredLight.isEmpty {
                            Divider().padding(.vertical, 4)
                        }
                        themeSection(title: "LIGHT", themes: filteredLight)
                        if filteredDark.isEmpty && filteredLight.isEmpty && !search.isEmpty {
                            emptyState
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selection) { _, newID in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .frame(height: 280)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    // MARK: - Keyboard navigation

    private var allVisibleThemes: [ThemePreview] {
        [ThemePreview.hexed] + filteredDark + filteredLight
    }

    private func moveSelection(by offset: Int) {
        let themes = allVisibleThemes
        guard !themes.isEmpty else { return }
        guard let idx = themes.firstIndex(where: { $0.id == selection }) else {
            selection = themes.first!.id
            return
        }
        let newIdx = min(max(idx + offset, 0), themes.count - 1)
        selection = themes[newIdx].id
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search themes...", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Hexed (pinned)

    private var hexedRow: some View {
        themeRow(ThemePreview.hexed)
    }

    // MARK: - Sections

    @ViewBuilder
    private func themeSection(title: String, themes: [ThemePreview]) -> some View {
        if !themes.isEmpty {
            sectionHeader(title, count: themes.count)
            ForEach(themes) { theme in
                themeRow(theme)
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Row

    private func themeRow(_ theme: ThemePreview) -> some View {
        let isSelected = selection == theme.id
        let isHovered = hoveredID == theme.id

        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(width: 16)

            Text(theme.name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            swatches(theme)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.12)
                      : isHovered ? Color.primary.opacity(0.06)
                      : .clear)
        )
        .id(theme.id)
        .contentShape(Rectangle())
        .onTapGesture { selection = theme.id }
        .onHover { hovering in hoveredID = hovering ? theme.id : nil }
    }

    // MARK: - Swatches

    private func swatches(_ theme: ThemePreview) -> some View {
        HStack(spacing: 3) {
            swatchCircle(theme.background)
            swatchCircle(theme.foreground)
            ForEach(Array(theme.sampleColors.enumerated()), id: \.offset) { _, color in
                swatchCircle(color)
            }
        }
    }

    private func swatchCircle(_ rgb: RGB) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Palette.color(rgb))
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Text("No themes matching \"\(search)\"")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    // MARK: - Filtering

    private var filteredDark: [ThemePreview] {
        filter(ThemePreview.darkThemes)
    }

    private var filteredLight: [ThemePreview] {
        filter(ThemePreview.lightThemes)
    }

    private func filter(_ themes: [ThemePreview]) -> [ThemePreview] {
        guard !search.isEmpty else { return themes }
        let query = search.lowercased()
        return themes.filter { $0.name.lowercased().contains(query) }
    }
}
