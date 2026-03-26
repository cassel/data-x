import SwiftUI
import AppKit

struct TreemapView: View {
    let node: FileNode
    let highlightedNode: FileNode?  // From file tree selection
    let onSelect: (FileNode) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var cachedRects: [TreemapRect] = []
    @State private var hoveredNode: FileNode?
    @State private var lastMouseLocation: CGPoint?
    @State private var lastUpdateTime: Date = .distantPast
    @State private var pulseExpanded = false
    @State private var zoomState = VisualizationZoomState()
    @GestureState private var zoomGesture = VisualizationZoomGestureState()

    private let maxDepth = 6
    private let throttleInterval: TimeInterval = 0.016 // ~60fps
    private let labelShadowColor = Color.black.opacity(0.35)
    private let labelShadowRadius: CGFloat = 1.5
    private let labelShadowYOffset: CGFloat = 1
    private let pulseScaleMax: CGFloat = 1.02
    private let pulseAnimation = Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)

    // Combined: hover takes priority, otherwise use highlighted from tree
    private var effectiveHighlight: FileNode? {
        hoveredNode ?? highlightedNode
    }

    private var pulseTargetRect: TreemapRect? {
        TreemapPulsePolicy.largestVisibleTopLevelRect(in: cachedRects)
    }

    private var shouldRenderPulse: Bool {
        TreemapPulsePolicy.shouldRenderPulse(
            reduceMotion: accessibilityReduceMotion,
            hasHover: hoveredNode != nil,
            hasHighlight: highlightedNode != nil
        )
    }

    private var currentPulseScale: CGFloat {
        shouldRenderPulse && pulseExpanded ? pulseScaleMax : 1
    }

    private var effectiveZoomScale: CGFloat {
        zoomState.effectiveScale(
            gestureMagnification: zoomGesture.magnification,
            reduceMotion: accessibilityReduceMotion
        )
    }

    private var effectiveZoomAnchor: UnitPoint {
        zoomState.effectiveAnchor(activeAnchor: zoomGesture.anchor)
    }

    private var zoomCompletionAnimation: Animation {
        if accessibilityReduceMotion {
            return .easeOut(duration: 0.12)
        }

        return .spring(response: 0.28, dampingFraction: 0.82)
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($zoomGesture) { value, state, _ in
                state = VisualizationZoomGestureState(
                    magnification: value.magnification,
                    anchor: value.startAnchor
                )
            }
            .onEnded { value in
                withAnimation(zoomCompletionAnimation) {
                    zoomState.commit(
                        gestureMagnification: value.magnification,
                        gestureAnchor: value.startAnchor
                    )
                }
            }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                // Static treemap layer - rasterized for performance
                Canvas { context, size in
                    drawTreemapStatic(context: &context, size: size)
                }
                .drawingGroup()

                // Hover overlay - lightweight
                Canvas { context, size in
                    drawHoverOverlay(context: context, size: size)
                }

                // Click handling
                interactionLayer()
            }
            .background(
                MouseTracker { location in
                    handleMouseMove(location, in: geometry.size)
                }
            )
            .overlay(alignment: .topLeading) {
                if let highlighted = effectiveHighlight {
                    InfoPanel(node: highlighted)
                        .offset(x: 10, y: 10)
                }
            }
            .onAppear {
                buildCache(size: geometry.size)
                configurePulseAnimation()
            }
            .onChange(of: geometry.size) { _, newSize in
                buildCache(size: newSize)
                refreshHoveredNode(in: newSize)
            }
            .onChange(of: node.id) { _, _ in
                resetZoom(animated: false)
                hoveredNode = nil
                lastMouseLocation = nil
                lastUpdateTime = .distantPast
                buildCache(size: geometry.size)
            }
            .onChange(of: accessibilityReduceMotion) { _, _ in
                configurePulseAnimation()
            }
            .onChange(of: zoomGesture) { _, _ in
                refreshHoveredNode(in: geometry.size)
            }
            .onChange(of: zoomState) { _, _ in
                refreshHoveredNode(in: geometry.size)
            }
            .simultaneousGesture(magnifyGesture)
        }
    }

    // MARK: - Mouse Handling

    private func handleMouseMove(_ location: CGPoint?, in viewSize: CGSize) {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= throttleInterval else { return }
        lastUpdateTime = now

        lastMouseLocation = location

        if let location {
            let contentPoint = VisualizationZoomState.contentPoint(
                for: location,
                in: viewSize,
                scale: effectiveZoomScale,
                anchor: effectiveZoomAnchor
            )
            hoveredNode = findHoveredNode(at: contentPoint)
        } else {
            hoveredNode = nil
        }
    }

    private func refreshHoveredNode(in viewSize: CGSize) {
        guard let lastMouseLocation else {
            hoveredNode = nil
            return
        }

        let contentPoint = VisualizationZoomState.contentPoint(
            for: lastMouseLocation,
            in: viewSize,
            scale: effectiveZoomScale,
            anchor: effectiveZoomAnchor
        )
        hoveredNode = findHoveredNode(at: contentPoint)
    }

    // MARK: - Cache

    private func buildCache(size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }

        // Adaptive max rects based on view size
        let maxRects = min(8000, Int(size.width * size.height / 50))

        cachedRects = TreemapLayout.layout(
            node: node,
            bounds: CGRect(origin: .zero, size: size),
            depth: 0,
            maxDepth: maxDepth,
            maxRects: maxRects
        )
    }

    private func findHoveredNode(at point: CGPoint) -> FileNode? {
        var deepest: TreemapRect?
        for rect in cachedRects {
            if rect.contains(point) {
                if deepest == nil || rect.depth > deepest!.depth {
                    deepest = rect
                }
            }
        }
        return deepest?.node
    }

    // MARK: - Static Drawing

    private func drawTreemapStatic(context: inout GraphicsContext, size: CGSize) {
        applyZoomTransform(to: &context, size: size)
        let pulseTargetID = pulseTargetRect?.id

        for rect in cachedRects {
            guard rect.id != pulseTargetID else { continue }
            drawStaticRect(rect, pulseScale: 1, context: &context)
        }

        if let pulseTargetRect, shouldRenderPulse {
            drawStaticRect(pulseTargetRect, pulseScale: currentPulseScale, context: &context)
        } else if let pulseTargetRect {
            drawStaticRect(pulseTargetRect, pulseScale: 1, context: &context)
        }
    }

    private func drawStaticRect(_ rect: TreemapRect, pulseScale: CGFloat, context: inout GraphicsContext) {
        let padding: CGFloat = rect.depth == 0 ? 1.0 : 0.5
        let insetRect = rect.cgRect.insetBy(dx: padding, dy: padding)
        guard insetRect.width > 0.5 && insetRect.height > 0.5 else { return }

        let cornerRadius: CGFloat = rect.depth == 0 ? 2 : 1
        let path = Path(roundedRect: insetRect, cornerRadius: cornerRadius)

        if pulseScale > 1 {
            context.drawLayer { layer in
                let center = CGPoint(x: insetRect.midX, y: insetRect.midY)
                layer.translateBy(x: center.x, y: center.y)
                layer.scaleBy(x: pulseScale, y: pulseScale)
                layer.translateBy(x: -center.x, y: -center.y)
                drawRectFillAndBorder(rect, path: path, context: &layer)
            }
        } else {
            drawRectFillAndBorder(rect, path: path, context: &context)
        }

        if rect.depth == 0 && insetRect.width > 50 && insetRect.height > 25 {
            drawLabel(rect, context: &context, insetRect: insetRect)
        }
    }

    private func drawRectFillAndBorder(_ rect: TreemapRect, path: Path, context: inout GraphicsContext) {
        context.fill(path, with: .color(rect.color))

        if rect.depth < 2 {
            context.stroke(path, with: .color(.black.opacity(0.2)), lineWidth: 0.5)
        }
    }

    // MARK: - Hover Overlay

    private func drawHoverOverlay(context: GraphicsContext, size: CGSize) {
        guard let highlighted = effectiveHighlight else { return }
        guard let highlightedRect = cachedRects.first(where: { $0.node.id == highlighted.id }) else { return }

        var context = context
        applyZoomTransform(to: &context, size: size)

        // Find top-level parent
        let parentRect = findTopLevelParent(of: highlightedRect)

        // Dim non-parent areas
        if let parent = parentRect {
            for rect in cachedRects where rect.depth == 0 && rect.id != parent.id {
                let path = Path(roundedRect: rect.cgRect.insetBy(dx: 1, dy: 1), cornerRadius: 2)
                context.fill(path, with: .color(.black.opacity(0.5)))
            }

            // Parent border
            let parentPath = Path(roundedRect: parent.cgRect.insetBy(dx: 1, dy: 1), cornerRadius: 2)
            context.stroke(parentPath, with: .color(.white.opacity(0.8)), lineWidth: 2)
        }

        // Highlighted item border (yellow for hover, cyan for tree selection)
        let padding: CGFloat = highlightedRect.depth == 0 ? 1.0 : 0.5
        let borderColor: Color = hoveredNode != nil ? .yellow : .cyan
        let highlightedPath = Path(roundedRect: highlightedRect.cgRect.insetBy(dx: padding, dy: padding), cornerRadius: highlightedRect.depth == 0 ? 2 : 1)
        context.stroke(highlightedPath, with: .color(borderColor), lineWidth: 2)
    }

    private func applyZoomTransform(to context: inout GraphicsContext, size: CGSize) {
        let scale = effectiveZoomScale
        guard abs(scale - 1) > 0.0001 else { return }

        let anchorPoint = VisualizationZoomState.anchorPoint(for: effectiveZoomAnchor, in: size)
        context.translateBy(x: anchorPoint.x, y: anchorPoint.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -anchorPoint.x, y: -anchorPoint.y)
    }

    private func findTopLevelParent(of rect: TreemapRect) -> TreemapRect? {
        if rect.depth == 0 { return rect }
        return cachedRects.first { $0.depth == 0 && $0.contains(rect.center) }
    }

    private func configurePulseAnimation() {
        guard !accessibilityReduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pulseExpanded = false
            }
            return
        }

        guard !pulseExpanded else { return }

        pulseExpanded = false
        withAnimation(pulseAnimation) {
            pulseExpanded = true
        }
    }

    private func handlePrimaryTap() {
        if let hoveredNode, hoveredNode.isDirectory {
            onSelect(hoveredNode)
        }
    }

    private func handleResetTap() {
        guard zoomState.canReset else { return }
        resetZoom(animated: true)
    }

    private func resetZoom(animated: Bool) {
        if animated {
            withAnimation(zoomCompletionAnimation) {
                zoomState.reset()
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            zoomState.reset()
        }
    }

    @ViewBuilder
    private func interactionLayer() -> some View {
        let surface = Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                handlePrimaryTap()
            }

        if zoomState.canReset {
            surface.highPriorityGesture(
                TapGesture(count: 2)
                    .onEnded(handleResetTap)
            )
        } else {
            surface
        }
    }

    // MARK: - Labels

    private func drawLabel(_ rect: TreemapRect, context: inout GraphicsContext, insetRect: CGRect) {
        let padding: CGFloat = 4
        let w = insetRect.width - padding * 2
        let h = insetRect.height - padding * 2
        guard w > 25, h > 12 else { return }

        let fontSize = min(max(9, h / 4), 12)
        let maxChars = Int(w / (fontSize * 0.55))
        var name = rect.node.name
        if name.count > maxChars {
            if maxChars < 3 { return }
            name = String(name.prefix(maxChars - 1)) + "…"
        }

        drawShadowedText(
            Text(name).font(.system(size: fontSize, weight: .medium)).foregroundColor(.white),
            at: CGPoint(x: insetRect.minX + padding, y: insetRect.minY + padding + fontSize / 2),
            context: &context
        )

        if h > 30 {
            drawShadowedText(
                Text(rect.node.formattedSize).font(.system(size: fontSize - 1)).foregroundColor(.white.opacity(0.8)),
                at: CGPoint(x: insetRect.minX + padding, y: insetRect.minY + padding + fontSize + 8),
                context: &context
            )
        }
    }

    private func drawShadowedText(_ text: Text, at point: CGPoint, context: inout GraphicsContext) {
        context.drawLayer { layer in
            layer.addFilter(
                .shadow(
                    color: labelShadowColor,
                    radius: labelShadowRadius,
                    x: 0,
                    y: labelShadowYOffset
                )
            )
            layer.draw(text, at: point, anchor: .leading)
        }
    }
}

struct TreemapPulsePolicy {
    static func largestVisibleTopLevelRect(in rects: [TreemapRect]) -> TreemapRect? {
        rects
            .lazy
            .filter { $0.depth == 0 && $0.area > 0 }
            .max { $0.area < $1.area }
    }

    static func shouldRenderPulse(reduceMotion: Bool, hasHover: Bool, hasHighlight: Bool) -> Bool {
        !reduceMotion && !hasHover && !hasHighlight
    }
}

struct VisualizationZoomGestureState: Equatable {
    var magnification: CGFloat = 1
    var anchor: UnitPoint?
}

struct VisualizationZoomState: Equatable {
    static let scaleRange: ClosedRange<CGFloat> = 1...5

    var committedScale: CGFloat = scaleRange.lowerBound
    var committedAnchor: UnitPoint = .center

    var canReset: Bool {
        Self.prefersResetDoubleTap(totalScale: committedScale)
    }

    func effectiveScale(gestureMagnification: CGFloat, reduceMotion: Bool) -> CGFloat {
        let rawScale = committedScale * gestureMagnification

        if reduceMotion {
            return Self.clamp(rawScale)
        }

        return Self.rubberBand(rawScale)
    }

    func effectiveAnchor(activeAnchor: UnitPoint?) -> UnitPoint {
        activeAnchor ?? committedAnchor
    }

    mutating func commit(gestureMagnification: CGFloat, gestureAnchor: UnitPoint?) {
        let finalScale = Self.clamp(committedScale * gestureMagnification)
        committedScale = finalScale

        if Self.prefersResetDoubleTap(totalScale: finalScale), let gestureAnchor {
            committedAnchor = gestureAnchor
        } else {
            committedAnchor = .center
        }
    }

    mutating func reset() {
        committedScale = Self.scaleRange.lowerBound
        committedAnchor = .center
    }

    static func prefersResetDoubleTap(totalScale: CGFloat) -> Bool {
        totalScale > scaleRange.lowerBound + 0.001
    }

    static func anchorPoint(for anchor: UnitPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)
    }

    static func viewPoint(
        for contentPoint: CGPoint,
        in size: CGSize,
        scale: CGFloat,
        anchor: UnitPoint
    ) -> CGPoint {
        let anchorPoint = anchorPoint(for: anchor, in: size)
        return CGPoint(
            x: anchorPoint.x + (contentPoint.x - anchorPoint.x) * scale,
            y: anchorPoint.y + (contentPoint.y - anchorPoint.y) * scale
        )
    }

    static func contentPoint(
        for viewPoint: CGPoint,
        in size: CGSize,
        scale: CGFloat,
        anchor: UnitPoint
    ) -> CGPoint {
        let anchorPoint = anchorPoint(for: anchor, in: size)
        guard abs(scale) > 0.0001 else { return viewPoint }

        return CGPoint(
            x: anchorPoint.x + (viewPoint.x - anchorPoint.x) / scale,
            y: anchorPoint.y + (viewPoint.y - anchorPoint.y) / scale
        )
    }

    private static func clamp(_ scale: CGFloat) -> CGFloat {
        min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
    }

    private static func rubberBand(_ scale: CGFloat) -> CGFloat {
        if scale < scaleRange.lowerBound {
            let overshoot = scaleRange.lowerBound - scale
            return scaleRange.lowerBound - rubberBandDistance(for: overshoot)
        }

        if scale > scaleRange.upperBound {
            let overshoot = scale - scaleRange.upperBound
            return scaleRange.upperBound + rubberBandDistance(for: overshoot)
        }

        return scale
    }

    private static func rubberBandDistance(for overshoot: CGFloat) -> CGFloat {
        let factor: CGFloat = 0.45
        let scaledOvershoot = overshoot * factor
        return scaledOvershoot / (scaledOvershoot + 1)
    }
}

// MARK: - Info Panel

struct InfoPanel: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(node.isDirectory ? FileCategory.folders.color : node.category.color)
                .frame(width: 10, height: 10)

            Text(node.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Text("•")
                .foregroundColor(.secondary)

            Text(node.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            if node.isDirectory {
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(node.fileCount) items")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(6)
    }
}

// MARK: - Mouse Tracker

struct MouseTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        TrackingNSView(onMove: onMove)
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMove = onMove
    }

    class TrackingNSView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        private var trackingArea: NSTrackingArea?

        init(onMove: ((CGPoint?) -> Void)?) {
            self.onMove = onMove
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let ta = trackingArea { removeTrackingArea(ta) }
            trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
            addTrackingArea(trackingArea!)
        }

        override func mouseMoved(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            onMove?(CGPoint(x: loc.x, y: bounds.height - loc.y))
        }

        override func mouseExited(with event: NSEvent) {
            onMove?(nil)
        }
    }
}

#Preview {
    TreemapView(node: FileNode(url: URL(fileURLWithPath: "/"), isDirectory: true), highlightedNode: nil) { _ in }
        .frame(width: 600, height: 400)
}
