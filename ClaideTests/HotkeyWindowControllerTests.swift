// ABOUTME: Tests for hotkey window positioning against synthetic screen rects.
// ABOUTME: Verifies frame calculation for all four edge positions and size percentages.

import Testing
import AppKit
@testable import Claide

@Suite("Hotkey Window Controller")
@MainActor
struct HotkeyWindowControllerTests {

    // Synthetic screen rect: 1920x1080 with 25px menu bar at top and 70px dock at bottom
    // visibleFrame origin is (0, 70), size is (1920, 985)
    private let screen = NSRect(x: 0, y: 70, width: 1920, height: 985)

    // MARK: - Position Calculations

    @Test("top position fills width, drops from top edge")
    func topPosition() {
        let frame = HotkeyWindowController.calculateFrame(
            position: .top, screenFrame: screen, sizePercent: 50
        )
        #expect(frame.origin.x == 0)
        #expect(frame.width == 1920)
        #expect(frame.height == 985 * 0.5)
        // Top edge: origin.y should place the window at the top of visible area
        #expect(frame.maxY == screen.maxY)
    }

    @Test("bottom position fills width, rises from bottom edge")
    func bottomPosition() {
        let frame = HotkeyWindowController.calculateFrame(
            position: .bottom, screenFrame: screen, sizePercent: 50
        )
        #expect(frame.origin.x == 0)
        #expect(frame.origin.y == 70)
        #expect(frame.width == 1920)
        #expect(frame.height == 985 * 0.5)
    }

    @Test("left position fills height, slides from left edge")
    func leftPosition() {
        let frame = HotkeyWindowController.calculateFrame(
            position: .left, screenFrame: screen, sizePercent: 40
        )
        #expect(frame.origin.x == 0)
        #expect(frame.origin.y == 70)
        #expect(frame.width == 1920 * 0.4)
        #expect(frame.height == 985)
    }

    @Test("right position fills height, slides from right edge")
    func rightPosition() {
        let frame = HotkeyWindowController.calculateFrame(
            position: .right, screenFrame: screen, sizePercent: 40
        )
        let expectedWidth: CGFloat = 1920 * 0.4
        #expect(frame.origin.x == CGFloat(1920) - expectedWidth)
        #expect(frame.origin.y == 70)
        #expect(frame.width == expectedWidth)
        #expect(frame.height == 985)
    }

    @Test("100% size fills entire visible area")
    func fullSize() {
        let frame = HotkeyWindowController.calculateFrame(
            position: .top, screenFrame: screen, sizePercent: 100
        )
        #expect(frame == screen)
    }

    @Test("offscreen frame for top is above visible area")
    func offscreenTop() {
        let target = HotkeyWindowController.calculateFrame(
            position: .top, screenFrame: screen, sizePercent: 50
        )
        let offscreen = HotkeyWindowController.offscreenFrame(
            position: .top, targetFrame: target, screenFrame: screen
        )
        #expect(offscreen.origin.y == screen.maxY)
        #expect(offscreen.size == target.size)
    }

    @Test("offscreen frame for bottom is below visible area")
    func offscreenBottom() {
        let target = HotkeyWindowController.calculateFrame(
            position: .bottom, screenFrame: screen, sizePercent: 50
        )
        let offscreen = HotkeyWindowController.offscreenFrame(
            position: .bottom, targetFrame: target, screenFrame: screen
        )
        #expect(offscreen.maxY == screen.origin.y)
        #expect(offscreen.size == target.size)
    }

    @Test("offscreen frame for left is left of visible area")
    func offscreenLeft() {
        let target = HotkeyWindowController.calculateFrame(
            position: .left, screenFrame: screen, sizePercent: 40
        )
        let offscreen = HotkeyWindowController.offscreenFrame(
            position: .left, targetFrame: target, screenFrame: screen
        )
        #expect(offscreen.maxX == screen.origin.x)
        #expect(offscreen.size == target.size)
    }

    @Test("offscreen frame for right is right of visible area")
    func offscreenRight() {
        let target = HotkeyWindowController.calculateFrame(
            position: .right, screenFrame: screen, sizePercent: 40
        )
        let offscreen = HotkeyWindowController.offscreenFrame(
            position: .right, targetFrame: target, screenFrame: screen
        )
        #expect(offscreen.origin.x == screen.maxX)
        #expect(offscreen.size == target.size)
    }
}
