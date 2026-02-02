// ABOUTME: Design reference for graph node appearance.
// ABOUTME: Not instantiated at runtime; nodes are drawn directly via Canvas in GraphPanel.

import SwiftUI

// Node rendering is handled entirely by GraphPanel's Canvas with zoom-adaptive
// detail via NodeMetrics. Zoom levels control progressive disclosure:
//
//   < 0.5  Type-colored shape blob only (no text)
//   0.5+   + Title text
//   0.6+   + ID text (top-left, colored by type)
//   0.65+  + Pill badges (type, status, priority)
//   0.7+   + Info row (owner, dep counts, age dot)
//
// Node layout at full zoom (200x80 graph-space):
//   +--[ proj-abc ]----[ Feature ][ Open ][ P2 ]--+
//   |                                               |
//   |  Title text (up to ~2 lines, clipped)         |
//   |                                               |
//   |  hex                          ->2 <-1     [*] |
//   +-----------------------------------------------+
//
// Borders encode type identity (color at 60% opacity) except blocked (red, 4x width).
// Status info is conveyed by pill badges, not border color.
