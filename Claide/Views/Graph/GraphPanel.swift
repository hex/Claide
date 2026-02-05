// ABOUTME: Interactive dependency graph with Canvas-drawn edges and draggable nodes.
// ABOUTME: Supports pan/zoom via magnification and scroll gestures.

import SwiftUI

/// Fixed graph-space dimensions with quality-level cutoffs.
/// Mirrors LiteGraph: nodes are always the same size, zoom scales uniformly.
struct NodeMetrics: Sendable {
    static let graphWidth: CGFloat = 200
    static let graphHeight: CGFloat = 80

    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let showTitle: Bool
    let showIdText: Bool
    let showBadges: Bool
    let showInfoRow: Bool
    let lowQuality: Bool

    static func at(zoom: CGFloat) -> NodeMetrics {
        let low = zoom < 0.6
        return NodeMetrics(
            width: graphWidth * zoom,
            height: graphHeight * zoom,
            cornerRadius: low ? 0 : 4 * zoom,
            showTitle: zoom >= 0.5,
            showIdText: zoom >= 0.6,
            showBadges: zoom >= 0.65,
            showInfoRow: zoom >= 0.7,
            lowQuality: low
        )
    }
}

struct GraphPanel: View {
    @Bindable var viewModel: GraphViewModel
    var fontFamily: String = ""

    @State private var zoom: CGFloat = 1.0
    @State private var zoomBase: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var activeDrag: ActiveDrag?
    @State private var selectedNodeID: String?
    @State private var preSelectZoom: CGFloat?
    @State private var preSelectPan: CGSize?
    @State private var cameraScale: CGFloat = 1.0
    @State private var cameraTranslation: CGSize = .zero
    @State private var showPopover = false
    @State private var popoverTask: Task<Void, Never>?

    private enum ActiveDrag {
        case pan(CGSize)
        case node(id: String, offset: CGSize)
    }

    /// Zoom toward a screen-space point, adjusting panOffset so the point stays fixed.
    /// Ports LiteGraph's DragAndScale.changeScale cursor-pivot behavior.
    private func zoomAt(screenPoint: CGPoint, newZoom: CGFloat, viewSize: CGSize) {
        let clamped = max(0.1, min(3.0, newZoom))
        // Convert screen point to graph-space before zoom change
        let offset = centeringOffset(in: viewSize)
        let graphX = (screenPoint.x - offset.x - panOffset.width) / zoom
        let graphY = (screenPoint.y - offset.y - panOffset.height) / zoom
        let oldZoom = zoom
        zoom = clamped
        // centeringOffset changes with zoom, recompute
        let newOffset = centeringOffset(in: viewSize)
        // Adjust pan so the graph point under cursor stays at the same screen position
        panOffset.width += (graphX * oldZoom + offset.x) - (graphX * clamped + newOffset.x)
        panOffset.height += (graphY * oldZoom + offset.y) - (graphY * clamped + newOffset.y)
        zoomBase = zoom
    }

    /// Animate the viewport to center on a specific node, zooming in if needed.
    /// Saves pre-selection camera state on first selection for later restore.
    /// Uses a compensating scaleEffect+offset for GPU-accelerated smooth animation.
    private func centerOn(id: String, in viewSize: CGSize) {
        guard let pos = viewModel.positions[id] else { return }
        let allPos = viewModel.issues.compactMap { viewModel.positions[$0.id] }
        guard !allPos.isEmpty else { return }
        let cx = allPos.map(\.x).reduce(0, +) / CGFloat(allPos.count)
        let cy = allPos.map(\.y).reduce(0, +) / CGFloat(allPos.count)
        if selectedNodeID == nil {
            preSelectZoom = zoom
            preSelectPan = panOffset
        }
        let newZoom = max(zoom, 0.8)
        let newPan = CGSize(
            width: (cx - pos.x) * newZoom,
            height: (cy - pos.y) * newZoom
        )
        animateCamera(toZoom: newZoom, toPan: newPan)
        selectedNodeID = id
        showPopover = false
        popoverTask?.cancel()
        popoverTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            if !Task.isCancelled, selectedNodeID != nil {
                showPopover = true
            }
        }
    }

    /// Animate back to the pre-selection camera state and clear selection.
    private func deselect() {
        popoverTask?.cancel()
        showPopover = false
        let restoreZoom = preSelectZoom ?? zoom
        let restorePan = preSelectPan ?? panOffset
        animateCamera(toZoom: restoreZoom, toPan: restorePan)
        selectedNodeID = nil
        preSelectZoom = nil
        preSelectPan = nil
    }

    /// Set Canvas to target state immediately, apply a compensating transform
    /// that makes it look like the old state, then animate the transform to identity.
    private func animateCamera(toZoom newZoom: CGFloat, toPan newPan: CGSize) {
        let scale = zoom / newZoom
        cameraScale = scale
        cameraTranslation = CGSize(
            width: panOffset.width - newPan.width * scale,
            height: panOffset.height - newPan.height * scale
        )
        zoom = newZoom
        zoomBase = newZoom
        panOffset = newPan
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraScale = 1.0
            cameraTranslation = .zero
        }
    }

    private var effectivePan: CGSize {
        var p = panOffset
        if case .pan(let drag) = activeDrag {
            p.width += drag.width
            p.height += drag.height
        }
        return p
    }

    /// Compute zoom level that fits all nodes within the viewport
    private func fitZoom(in viewSize: CGSize) -> CGFloat {
        let allPos = viewModel.issues.compactMap { viewModel.positions[$0.id] }
        guard allPos.count > 1 else { return 1.0 }

        let nodeWidth = NodeMetrics.graphWidth
        let nodeHeight = NodeMetrics.graphHeight
        let padding: CGFloat = 40

        let minX = allPos.map(\.x).min()! - nodeWidth / 2
        let maxX = allPos.map(\.x).max()! + nodeWidth / 2
        let minY = allPos.map(\.y).min()! - nodeHeight / 2
        let maxY = allPos.map(\.y).max()! + nodeHeight / 2

        let graphWidth = maxX - minX
        let graphHeight = maxY - minY

        let availableWidth = viewSize.width - padding * 2
        let availableHeight = viewSize.height - padding * 2

        guard graphWidth > 0, graphHeight > 0, availableWidth > 0, availableHeight > 0 else { return 1.0 }

        let fit = min(availableWidth / graphWidth, availableHeight / graphHeight)
        return max(0.1, min(fit, 1.0))
    }

    /// Compute the offset that centers the graph's bounding box in a given viewport
    private func centeringOffset(in viewSize: CGSize) -> CGPoint {
        let allPos = viewModel.issues.compactMap { viewModel.positions[$0.id] }
        guard !allPos.isEmpty else { return CGPoint(x: viewSize.width / 2, y: viewSize.height / 2) }
        let cx = allPos.map(\.x).reduce(0, +) / CGFloat(allPos.count)
        let cy = allPos.map(\.y).reduce(0, +) / CGFloat(allPos.count)
        return CGPoint(
            x: viewSize.width / 2 - cx * zoom,
            y: viewSize.height / 2 - cy * zoom
        )
    }

    /// Transform a model-space point to screen-space given a viewport size
    private func transformed(_ point: CGPoint, in viewSize: CGSize) -> CGPoint {
        let offset = centeringOffset(in: viewSize)
        return CGPoint(
            x: point.x * zoom + offset.x + effectivePan.width,
            y: point.y * zoom + offset.y + effectivePan.height
        )
    }

    var body: some View {
        PanelView {
            SectionHeader(title: "Dependencies", trailing: "\(viewModel.issues.count) issues")

            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.issues.isEmpty {
                emptyView
            } else {
                graphContent
            }
        }
    }

    private var graphContent: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let metrics = NodeMetrics.at(zoom: zoom)
                let edgeLineWidth = max(0.5, min(1.5, zoom))

                // Draw grid dots
                drawGrid(context: &context, in: size)

                // Pre-compute selection highlight set
                let highlightedIDs: Set<String> = {
                    guard let sel = selectedNodeID else { return [] }
                    return viewModel.neighbors(of: sel, hops: 2)
                }()

                // Draw edges
                for edge in viewModel.uniqueEdges {
                    guard let from = viewModel.positions[edge.from],
                          let to = viewModel.positions[edge.to] else { continue }

                    var fromPt = transformed(from, in: size)
                    var toPt = transformed(to, in: size)

                    if case .node(let id, let offset) = activeDrag {
                        if edge.from == id {
                            fromPt.x += offset.width
                            fromPt.y += offset.height
                        }
                        if edge.to == id {
                            toPt.x += offset.width
                            toPt.y += offset.height
                        }
                    }

                    let ev = EdgeVisuals.compute(for: edge.type)

                    // Dim edges not connected to selection
                    let edgeDimmed = selectedNodeID != nil
                        && edge.from != selectedNodeID
                        && edge.to != selectedNodeID
                        && !highlightedIDs.contains(edge.from)
                        && !highlightedIDs.contains(edge.to)
                    let edgeColor = edgeDimmed ? ev.color.opacity(0.15) : ev.color

                    var linePath = Path()
                    linePath.move(to: fromPt)
                    linePath.addLine(to: toPt)

                    if ev.isDashed {
                        let dashStyle = StrokeStyle(
                            lineWidth: edgeLineWidth,
                            dash: [4 * zoom, 4 * zoom]
                        )
                        context.stroke(linePath, with: .color(edgeColor), style: dashStyle)
                    } else {
                        context.stroke(linePath, with: .color(edgeColor), lineWidth: edgeLineWidth)
                    }

                    // Arrowhead at target
                    if ev.hasArrowhead {
                        let arrowPath = EdgeVisuals.arrowheadPath(
                            from: fromPt, to: toPt, size: 8 * zoom
                        )
                        context.stroke(arrowPath, with: .color(edgeColor), lineWidth: edgeLineWidth)
                    }
                }

                // Draw nodes
                let textFont: Font = fontFamily.isEmpty
                    ? .system(size: 10 * zoom)
                    : .custom(fontFamily, size: 10 * zoom)
                let boldFont: Font = fontFamily.isEmpty
                    ? .system(size: 10 * zoom, weight: .bold)
                    : .custom(fontFamily, size: 10 * zoom).bold()
                let badgeFont: Font = .system(size: 7 * zoom, weight: .semibold)
                let smallFont: Font = .system(size: 8 * zoom)

                for issue in viewModel.issues {
                    guard let pos = viewModel.positions[issue.id] else { continue }
                    var pt = transformed(pos, in: size)

                    if case .node(let id, let offset) = activeDrag, id == issue.id {
                        pt.x += offset.width
                        pt.y += offset.height
                    }

                    // Size scaled by dependent count
                    let factor = NodeVisuals.sizeFactor(for: issue)
                    let nodeW = metrics.width * factor
                    let nodeH = metrics.height * factor

                    let rect = CGRect(
                        x: pt.x - nodeW / 2,
                        y: pt.y - nodeH / 2,
                        width: nodeW,
                        height: nodeH
                    )

                    let nodePath = metrics.lowQuality
                        ? Path(rect)
                        : Path(roundedRect: rect, cornerRadius: metrics.cornerRadius)

                    // Selection glow
                    let isSelected = selectedNodeID == issue.id
                    let isNeighbor = highlightedIDs.contains(issue.id)

                    if isSelected {
                        let glowPath = nodePath.strokedPath(.init(lineWidth: 6 * zoom))
                        context.fill(glowPath, with: .color(Theme.selectionGlow.opacity(0.3)))
                    } else if isNeighbor {
                        let glowPath = nodePath.strokedPath(.init(lineWidth: 4 * zoom))
                        context.fill(glowPath, with: .color(Theme.selectionGlow.opacity(0.15)))
                    }

                    // Fill: type color at low zoom, panel background at detail zoom
                    let fillColor = metrics.lowQuality
                        ? issue.typeColor.opacity(0.5)
                        : Theme.backgroundSunken
                    context.fill(nodePath, with: .color(fillColor))

                    // Border
                    let borderColor = NodeVisuals.borderColor(for: issue, in: viewModel.issues)
                    let strokeWidth = NodeVisuals.borderWidth(for: issue, in: viewModel.issues)
                    context.stroke(nodePath, with: .color(borderColor), lineWidth: strokeWidth)

                    // Dim unrelated nodes when something is selected
                    if selectedNodeID != nil && !isSelected && !isNeighbor {
                        context.fill(nodePath, with: .color(Theme.backgroundPrimary.opacity(0.5)))
                    }

                    let padding = 10 * zoom

                    // ID text (top-left, colored by type)
                    if metrics.showIdText {
                        let idText = Text(issue.id)
                            .font(boldFont)
                            .foregroundStyle(issue.typeColor)
                        context.draw(
                            context.resolve(idText),
                            at: CGPoint(x: rect.minX + padding, y: pt.y - 26 * zoom),
                            anchor: .leading
                        )
                    }

                    // Pill badges (top-right, right-to-left: priority, status, type)
                    if metrics.showBadges {
                        let charW = 4.5 * zoom
                        let pillH = 10 * zoom
                        let pillPadX = 3 * zoom
                        let pillGap = 2 * zoom
                        let pillY = pt.y - 26 * zoom - pillH / 2

                        var cursorX = rect.maxX - padding

                        let badges: [(String, BadgeColors)] = [
                            (NodeVisuals.priorityLabel(for: issue), issue.priorityBadge),
                            (issue.status == "in_progress" ? "Active" : issue.status.capitalized, issue.statusBadge),
                            (issue.issueType.capitalized, issue.typeBadge),
                        ]

                        for (label, colors) in badges {
                            let pillW = CGFloat(label.count) * charW + pillPadX * 2
                            let pillRect = CGRect(
                                x: cursorX - pillW,
                                y: pillY,
                                width: pillW,
                                height: pillH
                            )
                            let pillPath = Path(roundedRect: pillRect, cornerRadius: 3 * zoom)
                            context.fill(pillPath, with: .color(colors.bg))
                            context.stroke(pillPath, with: .color(colors.border), lineWidth: 0.5 * zoom)

                            let pillText = Text(label)
                                .font(badgeFont)
                                .foregroundStyle(colors.fg)
                            context.draw(
                                context.resolve(pillText),
                                at: CGPoint(x: pillRect.midX, y: pillRect.midY),
                                anchor: .center
                            )

                            cursorX -= pillW + pillGap
                        }
                    }

                    // Title
                    if metrics.showTitle {
                        let titleText = Text(issue.title)
                            .font(textFont)
                            .foregroundStyle(Theme.textPrimary)
                        context.draw(
                            context.resolve(titleText),
                            in: CGRect(
                                x: rect.minX + padding,
                                y: pt.y - 14 * zoom,
                                width: nodeW - padding * 2,
                                height: 30 * zoom
                            )
                        )
                    }

                    // Info row: owner left, dep counts right, age dot far-right
                    if metrics.showInfoRow {
                        let rowY = pt.y + 28 * zoom

                        // Owner (left)
                        if let ownerName = issue.ownerDisplay {
                            let ownerText = Text(ownerName)
                                .font(smallFont)
                                .foregroundStyle(Theme.textMuted)
                            context.draw(
                                context.resolve(ownerText),
                                at: CGPoint(x: rect.minX + padding, y: rowY),
                                anchor: .leading
                            )
                        }

                        // Dep counts (right of center)
                        if let depLabel = NodeVisuals.depCountLabel(for: issue) {
                            let depText = Text(depLabel)
                                .font(smallFont)
                                .foregroundStyle(Theme.textMuted)
                            context.draw(
                                context.resolve(depText),
                                at: CGPoint(x: rect.maxX - padding - 12 * zoom, y: rowY),
                                anchor: .trailing
                            )
                        }

                        // Age indicator dot (far right)
                        if let ageCol = NodeVisuals.ageColor(for: issue) {
                            let dotR = 3 * zoom
                            let dotPath = Path(ellipseIn: CGRect(
                                x: rect.maxX - padding - dotR * 2,
                                y: rowY - dotR,
                                width: dotR * 2,
                                height: dotR * 2
                            ))
                            context.fill(dotPath, with: .color(ageCol))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if let id = hitTestNode(at: value.location, in: geo.size) {
                            if selectedNodeID == id {
                                deselect()
                            } else {
                                centerOn(id: id, in: geo.size)
                            }
                        } else if selectedNodeID != nil {
                            deselect()
                        }
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if activeDrag == nil {
                            if let hitID = hitTestNode(at: value.startLocation, in: geo.size) {
                                activeDrag = .node(id: hitID, offset: value.translation)
                            } else {
                                activeDrag = .pan(value.translation)
                            }
                        } else {
                            switch activeDrag {
                            case .node(let id, _):
                                activeDrag = .node(id: id, offset: value.translation)
                            case .pan:
                                activeDrag = .pan(value.translation)
                            case .none:
                                break
                            }
                        }
                    }
                    .onEnded { value in
                        switch activeDrag {
                        case .node(let id, _):
                            if let pos = viewModel.positions[id] {
                                viewModel.positions[id] = CGPoint(
                                    x: pos.x + value.translation.width / zoom,
                                    y: pos.y + value.translation.height / zoom
                                )
                            }
                        case .pan:
                            panOffset.width += value.translation.width
                            panOffset.height += value.translation.height
                        case .none:
                            break
                        }
                        activeDrag = nil
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = max(0.1, min(3.0, zoomBase * value.magnification))
                    }
                    .onEnded { _ in
                        zoomBase = zoom
                    }
            )
            .scaleEffect(cameraScale)
            .offset(cameraTranslation)
            .clipped()
            .popover(isPresented: Binding(
                get: { showPopover && selectedNodeID != nil },
                set: { if !$0 { deselect() } }
            ), attachmentAnchor: .rect(.rect(selectedNodeAnchorRect(in: geo.size)))) {
                if let id = selectedNodeID,
                   let issue = viewModel.issues.first(where: { $0.id == id }) {
                    IssueDetailPopover(issue: issue)
                }
            }
            .background(ScrollWheelZoom { delta, cursorPoint in
                let zoomFactor: CGFloat = delta > 0 ? 1.1 : 1.0 / 1.1
                zoomAt(screenPoint: cursorPoint, newZoom: zoom * zoomFactor, viewSize: geo.size)
            })
            .onAppear {
                if !viewModel.issues.isEmpty {
                    zoom = fitZoom(in: geo.size)
                    zoomBase = zoom
                }
            }
            .onChange(of: viewModel.layoutGeneration) {
                zoom = fitZoom(in: geo.size)
                zoomBase = zoom
                panOffset = .zero
                activeDrag = nil
                selectedNodeID = nil
                preSelectZoom = nil
                preSelectPan = nil
                cameraScale = 1.0
                cameraTranslation = .zero
                popoverTask?.cancel()
                showPopover = false
            }
        }
        .frame(minHeight: 300)
    }

    /// Draw line grid behind all graph content. Spacing adapts to zoom so lines
    /// stay ~40-80 screen pixels apart regardless of zoom level.
    private func drawGrid(context: inout GraphicsContext, in size: CGSize) {
        let baseSpacing: CGFloat = 12
        var spacing = baseSpacing
        while spacing * zoom < 10 { spacing *= 2 }

        let offset = centeringOffset(in: size)
        let pan = effectivePan

        // Visible graph-space bounds
        let minGX = (0 - offset.x - pan.width) / zoom
        let maxGX = (size.width - offset.x - pan.width) / zoom
        let minGY = (0 - offset.y - pan.height) / zoom
        let maxGY = (size.height - offset.y - pan.height) / zoom

        let firstX = floor(minGX / spacing) * spacing
        let firstY = floor(minGY / spacing) * spacing

        var gridPath = Path()

        // Vertical lines
        var gx = firstX
        while gx <= maxGX {
            let screenX = gx * zoom + offset.x + pan.width
            gridPath.move(to: CGPoint(x: screenX, y: 0))
            gridPath.addLine(to: CGPoint(x: screenX, y: size.height))
            gx += spacing
        }

        // Horizontal lines
        var gy = firstY
        while gy <= maxGY {
            let screenY = gy * zoom + offset.y + pan.height
            gridPath.move(to: CGPoint(x: 0, y: screenY))
            gridPath.addLine(to: CGPoint(x: size.width, y: screenY))
            gy += spacing
        }

        context.stroke(gridPath, with: .color(Theme.backgroundSunken), lineWidth: 0.5)
    }

    /// Anchor rect matching the selected node's screen bounds for popover positioning.
    private func selectedNodeAnchorRect(in viewSize: CGSize) -> CGRect {
        guard let id = selectedNodeID,
              let pos = viewModel.positions[id] else {
            return CGRect(x: viewSize.width / 2, y: viewSize.height / 2, width: 1, height: 1)
        }
        let screenPt = transformed(pos, in: viewSize)
        let metrics = NodeMetrics.at(zoom: zoom)
        return CGRect(
            x: screenPt.x - metrics.width / 2,
            y: screenPt.y - metrics.height / 2,
            width: metrics.width,
            height: metrics.height
        )
    }

    /// Hit-test against node positions to find which node (if any) is at the given point.
    /// Accounts for variable node sizes from size-by-metric scaling.
    private func hitTestNode(at point: CGPoint, in viewSize: CGSize) -> String? {
        let metrics = NodeMetrics.at(zoom: zoom)
        for issue in viewModel.issues {
            guard let pos = viewModel.positions[issue.id] else { continue }
            let tp = transformed(pos, in: viewSize)
            let factor = NodeVisuals.sizeFactor(for: issue)
            let w = metrics.width * factor
            let h = metrics.height * factor
            let rect = CGRect(
                x: tp.x - w / 2,
                y: tp.y - h / 2,
                width: w,
                height: h
            )
            if rect.contains(point) {
                return issue.id
            }
        }
        return nil
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.6)
            Text("LOADING")
                .font(Theme.labelFont)
                .foregroundStyle(Theme.textSecondary)
                .tracking(1.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("ERROR")
                .font(Theme.labelFont)
                .foregroundStyle(Theme.negative)
                .tracking(1.5)
            Text(message)
                .font(Theme.bodyFontSmall)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        EmptyStateView(dataSource: viewModel.dataSource)
    }
}

/// Captures macOS scroll wheel events for zoom control.
/// Uses a local event monitor so it doesn't intercept drag events.
private struct ScrollWheelZoom: NSViewRepresentable {
    var onScroll: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

/// NSView that installs a local event monitor for scroll wheel events
/// within its bounds. Returns nil from hitTest so it never blocks mouse events.
private class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat, CGPoint) -> Void)?
    private var monitor: Any?

    override func hitTest(_ aPoint: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let loc = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(loc),
                   abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
                    // NSView Y is flipped (origin at bottom-left), convert to SwiftUI (top-left)
                    let flipped = CGPoint(x: loc.x, y: self.bounds.height - loc.y)
                    self.onScroll?(event.scrollingDeltaY, flipped)
                }
                return event
            }
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
