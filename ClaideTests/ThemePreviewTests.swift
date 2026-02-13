// ABOUTME: Tests for ThemePreview parsing from Ghostty theme files.
// ABOUTME: Verifies hex extraction, dark/light classification, and collection building.

import Testing
@testable import Claide

@Suite("ThemePreview")
struct ThemePreviewTests {

    // MARK: - Single theme parsing

    @Test("Parses Dracula theme correctly")
    func parseDracula() {
        let content = """
        palette = 0=#21222c
        palette = 1=#ff5555
        palette = 2=#50fa7b
        palette = 3=#f1fa8c
        palette = 4=#bd93f9
        palette = 5=#ff79c6
        palette = 6=#8be9fd
        palette = 7=#f8f8f2
        background = #282a36
        foreground = #f8f8f2
        """
        let preview = ThemePreview.parse(id: "Dracula", content: content)
        #expect(preview != nil)
        #expect(preview!.name == "Dracula")
        #expect(preview!.background == RGB(hex: "#282a36"))
        #expect(preview!.foreground == RGB(hex: "#f8f8f2"))
        #expect(preview!.isDark == true)
    }

    @Test("Parses light theme correctly")
    func parseLight() {
        let content = """
        palette = 0=#090300
        palette = 1=#db2d20
        palette = 2=#01a252
        palette = 3=#caba00
        palette = 4=#01a0e4
        background = #f7f7f7
        foreground = #4a4543
        """
        let preview = ThemePreview.parse(id: "3024 Day", content: content)
        #expect(preview != nil)
        #expect(preview!.isDark == false)
    }

    @Test("Extracts sample colors from palette entries 1-4")
    func sampleColors() {
        let content = """
        palette = 1=#ff5555
        palette = 2=#50fa7b
        palette = 3=#f1fa8c
        palette = 4=#bd93f9
        background = #282a36
        foreground = #f8f8f2
        """
        let preview = ThemePreview.parse(id: "Test", content: content)!
        #expect(preview.sampleColors.count == 4)
        #expect(preview.sampleColors[0] == RGB(hex: "#ff5555"))
        #expect(preview.sampleColors[1] == RGB(hex: "#50fa7b"))
        #expect(preview.sampleColors[2] == RGB(hex: "#f1fa8c"))
        #expect(preview.sampleColors[3] == RGB(hex: "#bd93f9"))
    }

    @Test("Returns nil when background missing")
    func missingBackground() {
        let content = "foreground = #f8f8f2"
        #expect(ThemePreview.parse(id: "Bad", content: content) == nil)
    }

    @Test("Returns nil when foreground missing")
    func missingForeground() {
        let content = "background = #282a36"
        #expect(ThemePreview.parse(id: "Bad", content: content) == nil)
    }

    // MARK: - Hexed preview

    @Test("Hexed preview uses Hexed ANSI data")
    func hexedPreview() {
        let h = ThemePreview.hexed
        #expect(h.id == "hexed")
        #expect(h.name == "Hexed")
        #expect(h.background == ChromeColorScheme.hexed.background)
        #expect(h.foreground == ChromeColorScheme.hexed.foreground)
        #expect(h.isDark == true)
        #expect(h.sampleColors.count == 4)
    }

    // MARK: - Static collections

    @Test("ghosttyThemes is non-empty")
    func ghosttyThemesPopulated() {
        #expect(ThemePreview.ghosttyThemes.count > 400)
    }

    @Test("darkThemes and lightThemes partition ghosttyThemes")
    func darkLightPartition() {
        let totalGhostty = ThemePreview.ghosttyThemes.count
        let dark = ThemePreview.darkThemes.count
        let light = ThemePreview.lightThemes.count
        #expect(dark + light == totalGhostty)
        #expect(dark > 0)
        #expect(light > 0)
    }

    @Test("Themes are sorted by name")
    func sorted() {
        let names = ThemePreview.ghosttyThemes.map(\.name)
        #expect(names == names.sorted())
    }
}
