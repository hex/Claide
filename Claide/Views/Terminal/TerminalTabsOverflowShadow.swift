// ABOUTME: Gradient shadow indicator for scrollable tab overflow.
// ABOUTME: Fades from the tab bar background color to transparent at the edge.

import SwiftUI

struct TerminalTabsOverflowShadow: View {
    let width: CGFloat
    let startPoint: UnitPoint
    let endPoint: UnitPoint

    var body: some View {
        LinearGradient(
            colors: [Theme.backgroundSunken, Theme.backgroundSunken.opacity(0)],
            startPoint: startPoint,
            endPoint: endPoint
        )
        .frame(width: width)
        .allowsHitTesting(false)
    }
}
