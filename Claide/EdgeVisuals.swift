// ABOUTME: Computes visual properties for graph edges from dependency type.
// ABOUTME: Maps "blocks" to solid red with arrowheads, "parent-child" to dashed gray.

import SwiftUI

struct EdgeVisualsResult: Equatable {
    let color: Color
    let isDashed: Bool
    let hasArrowhead: Bool
}

enum EdgeVisuals {

    static func compute(for edgeType: String) -> EdgeVisualsResult {
        switch edgeType {
        case "blocks":
            return EdgeVisualsResult(
                color: Theme.edgeBlocks,
                isDashed: false,
                hasArrowhead: true
            )
        case "parent-child":
            return EdgeVisualsResult(
                color: Theme.edgeDefault,
                isDashed: true,
                hasArrowhead: false
            )
        default:
            return EdgeVisualsResult(
                color: Theme.edgeDefault,
                isDashed: false,
                hasArrowhead: true
            )
        }
    }

    /// Draw an arrowhead at the target point, pointing from source to target.
    static func arrowheadPath(from source: CGPoint, to target: CGPoint, size: CGFloat) -> Path {
        let angle = atan2(target.y - source.y, target.x - source.x)
        let spread: CGFloat = .pi / 6 // 30 degrees

        var path = Path()
        path.move(to: target)
        path.addLine(to: CGPoint(
            x: target.x - size * cos(angle - spread),
            y: target.y - size * sin(angle - spread)
        ))
        path.move(to: target)
        path.addLine(to: CGPoint(
            x: target.x - size * cos(angle + spread),
            y: target.y - size * sin(angle + spread)
        ))
        return path
    }
}
