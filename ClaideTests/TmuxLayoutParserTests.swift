// ABOUTME: Tests for TmuxLayoutParser — tmux layout descriptor to pane tree.
// ABOUTME: Covers single pane, splits, nesting, checksum stripping, and edge cases.

import Testing
@testable import Claide

@Suite("TmuxLayoutParser — single pane")
struct TmuxLayoutSinglePaneTests {

    @Test("single pane with checksum")
    func singlePaneWithChecksum() throws {
        let node = try #require(TmuxLayoutParser.parse("bb62,159x48,0,0,5"))
        guard case .leaf(let w, let h, let x, let y, let paneID) = node else {
            Issue.record("Expected leaf node")
            return
        }
        #expect(w == 159)
        #expect(h == 48)
        #expect(x == 0)
        #expect(y == 0)
        #expect(paneID == 5)
    }

    @Test("single pane without checksum")
    func singlePaneNoChecksum() throws {
        let node = try #require(TmuxLayoutParser.parse("159x48,0,0,5"))
        guard case .leaf(_, _, _, _, let paneID) = node else {
            Issue.record("Expected leaf node")
            return
        }
        #expect(paneID == 5)
    }
}

@Suite("TmuxLayoutParser — horizontal splits")
struct TmuxLayoutHorizontalTests {

    @Test("two horizontal panes")
    func twoHorizontalPanes() throws {
        let layout = "161x48,0,0{80x48,0,0,0,80x48,81,0,1}"
        let node = try #require(TmuxLayoutParser.parse(layout))
        guard case .horizontal(let w, let h, _, _, let children) = node else {
            Issue.record("Expected horizontal node")
            return
        }
        #expect(w == 161)
        #expect(h == 48)
        #expect(children.count == 2)

        guard case .leaf(80, 48, 0, 0, 0) = children[0] else {
            Issue.record("Expected left pane with ID 0")
            return
        }
        guard case .leaf(80, 48, 81, 0, 1) = children[1] else {
            Issue.record("Expected right pane with ID 1")
            return
        }
    }

    @Test("three horizontal panes")
    func threeHorizontalPanes() throws {
        let layout = "120x40,0,0{40x40,0,0,0,40x40,41,0,1,38x40,82,0,2}"
        let node = try #require(TmuxLayoutParser.parse(layout))
        guard case .horizontal(_, _, _, _, let children) = node else {
            Issue.record("Expected horizontal node")
            return
        }
        #expect(children.count == 3)
    }
}

@Suite("TmuxLayoutParser — vertical splits")
struct TmuxLayoutVerticalTests {

    @Test("two vertical panes")
    func twoVerticalPanes() throws {
        let layout = "80x48,0,0[80x24,0,0,0,80x23,0,25,1]"
        let node = try #require(TmuxLayoutParser.parse(layout))
        guard case .vertical(_, _, _, _, let children) = node else {
            Issue.record("Expected vertical node")
            return
        }
        #expect(children.count == 2)

        guard case .leaf(80, 24, 0, 0, 0) = children[0] else {
            Issue.record("Expected top pane")
            return
        }
        guard case .leaf(80, 23, 0, 25, 1) = children[1] else {
            Issue.record("Expected bottom pane")
            return
        }
    }
}

@Suite("TmuxLayoutParser — nested splits")
struct TmuxLayoutNestedTests {

    @Test("horizontal with nested vertical")
    func horizontalWithNestedVertical() throws {
        let layout = "80x24,0,0{40x24,0,0,1,39x24,41,0[39x12,41,0,2,39x11,41,13,3]}"
        let node = try #require(TmuxLayoutParser.parse(layout))
        guard case .horizontal(_, _, _, _, let children) = node else {
            Issue.record("Expected horizontal node")
            return
        }
        #expect(children.count == 2)

        // Left pane is a leaf
        guard case .leaf(40, 24, 0, 0, 1) = children[0] else {
            Issue.record("Expected left leaf pane")
            return
        }

        // Right is a vertical split
        guard case .vertical(39, 24, 41, 0, let innerChildren) = children[1] else {
            Issue.record("Expected right vertical split")
            return
        }
        #expect(innerChildren.count == 2)
        guard case .leaf(39, 12, 41, 0, 2) = innerChildren[0] else {
            Issue.record("Expected top-right pane")
            return
        }
        guard case .leaf(39, 11, 41, 13, 3) = innerChildren[1] else {
            Issue.record("Expected bottom-right pane")
            return
        }
    }

    @Test("deeply nested layout")
    func deeplyNested() throws {
        // A{B[C{D,E},F],G}
        let layout = "100x50,0,0{50x50,0,0[25x25,0,0{12x25,0,0,0,12x25,13,0,1},25x24,0,26,2],49x50,51,0,3}"
        let node = try #require(TmuxLayoutParser.parse(layout))
        let paneIDs = node.allPaneIDs
        #expect(paneIDs.sorted() == [0, 1, 2, 3])
    }
}

@Suite("TmuxLayoutParser — helper methods")
struct TmuxLayoutHelperTests {

    @Test("allPaneIDs collects all leaf pane IDs")
    func allPaneIDs() throws {
        let layout = "80x24,0,0{40x24,0,0,1,39x24,41,0[39x12,41,0,2,39x11,41,13,3]}"
        let node = try #require(TmuxLayoutParser.parse(layout))
        #expect(node.allPaneIDs.sorted() == [1, 2, 3])
    }

    @Test("invalid layout returns nil")
    func invalidLayout() {
        #expect(TmuxLayoutParser.parse("") == nil)
        #expect(TmuxLayoutParser.parse("garbage") == nil)
        #expect(TmuxLayoutParser.parse("xxx") == nil)
    }

    @Test("parentAxis returns horizontal for pane in horizontal split")
    func parentAxisHorizontal() throws {
        // {pane0, pane1} — horizontal split
        let layout = "161x48,0,0{80x48,0,0,0,80x48,81,0,1}"
        let node = try #require(TmuxLayoutParser.parse(layout))
        #expect(node.parentAxis(of: 0) == .horizontal)
        #expect(node.parentAxis(of: 1) == .horizontal)
    }

    @Test("parentAxis returns vertical for pane in vertical split")
    func parentAxisVertical() throws {
        // [pane0, pane1] — vertical split
        let layout = "80x48,0,0[80x24,0,0,0,80x23,0,25,1]"
        let node = try #require(TmuxLayoutParser.parse(layout))
        #expect(node.parentAxis(of: 0) == .vertical)
        #expect(node.parentAxis(of: 1) == .vertical)
    }

    @Test("parentAxis returns correct axis in nested layout")
    func parentAxisNested() throws {
        // {pane1, [pane2, pane3]} — pane1 is in horizontal, pane2/3 are in vertical
        let layout = "80x24,0,0{40x24,0,0,1,39x24,41,0[39x12,41,0,2,39x11,41,13,3]}"
        let node = try #require(TmuxLayoutParser.parse(layout))
        #expect(node.parentAxis(of: 1) == .horizontal)
        #expect(node.parentAxis(of: 2) == .vertical)
        #expect(node.parentAxis(of: 3) == .vertical)
    }

    @Test("parentAxis returns nil for root single pane")
    func parentAxisSinglePane() throws {
        let node = try #require(TmuxLayoutParser.parse("159x48,0,0,5"))
        #expect(node.parentAxis(of: 5) == nil)
    }

    @Test("parentAxis returns nil for unknown pane ID")
    func parentAxisUnknown() throws {
        let layout = "161x48,0,0{80x48,0,0,0,80x48,81,0,1}"
        let node = try #require(TmuxLayoutParser.parse(layout))
        #expect(node.parentAxis(of: 999) == nil)
    }
}
