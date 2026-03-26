import SwiftUI
import AppKit

struct TreemapView: View {
    let node: FileNode
    let highlightedNode: FileNode?  // From file tree selection
    let onSelect: (FileNode) -> Void
    let layoutRevision: Int
    let incrementalScanInProgress: Bool
    let onMoveToTrash: (FileNode) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AccessibilityFocusState private var accessibilityFocusedRectID: UUID?
    @FocusState private var isTreemapFocused: Bool
    @State private var hitTestCache = TreemapHitTestCache.empty
    @State private var hoveredNode: FileNode?
    @State private var keyboardFocusedRectID: UUID?
    @State private var lastMouseLocation: CGPoint?
    @State private var lastUpdateTime: Date = .distantPast
    @State private var rendererRevision = 0
    @State private var animateStructuralChanges = false
    @State private var pulseExpanded = false
    @State private var deletionAnimation: TreemapDeletionAnimation?
    @State private var layoutAnimation: TreemapLayoutAnimation?
    @State private var lastViewSize: CGSize = .zero
    @State private var zoomState = VisualizationZoomState()
    @GestureState private var zoomGesture = VisualizationZoomGestureState()

    private let maxDepth = 6
    private let throttleInterval: TimeInterval = 0.016 // ~60fps
    private let labelShadowColor = Color.black.opacity(0.35)
    private let labelShadowRadius: CGFloat = 1.5
    private let labelShadowYOffset: CGFloat = 1
    private let pulseScaleMax: CGFloat = 1.02
    private let pulseAnimation = Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)

    private var cachedRects: [TreemapRect] {
        hitTestCache.rects
    }

    private var treemapAccessibilityNodes: [TreemapAccessibilityNode] {
        cachedRects.map {
            TreemapAccessibilityNode(
                id: $0.id,
                frame: $0.displayRect,
                depth: $0.depth
            )
        }
    }

    private var keyboardFocusedNode: FileNode? {
        guard let keyboardFocusedRectID,
              let rect = activeRect(for: keyboardFocusedRectID),
              !isAnimatingRemoval(for: rect.node) else {
            return nil
        }

        return rect.node
    }

    // Combined: hover takes priority, then keyboard focus, then file-tree selection.
    private var effectiveHighlight: TreemapHighlightState? {
        if let hoveredNode,
           !isAnimatingRemoval(for: hoveredNode),
           activeRect(for: hoveredNode.id) != nil {
            return TreemapHighlightState(node: hoveredNode, source: .hover)
        }

        if let keyboardFocusedNode {
            return TreemapHighlightState(node: keyboardFocusedNode, source: .keyboard)
        }

        if let highlightedNode,
           !isAnimatingRemoval(for: highlightedNode),
           activeRect(for: highlightedNode.id) != nil {
            return TreemapHighlightState(node: highlightedNode, source: .treeSelection)
        }

        return nil
    }

    private var pulseTargetRect: TreemapRect? {
        guard deletionAnimation == nil, layoutAnimation == nil else { return nil }
        return TreemapPulsePolicy.largestVisibleTopLevelRect(in: cachedRects)
    }

    private var shouldRenderPulse: Bool {
        TreemapPulsePolicy.shouldRenderPulse(
            reduceMotion: accessibilityReduceMotion,
            hasHover: hoveredNode != nil,
            hasHighlight: highlightedNode != nil
        ) && deletionAnimation == nil && layoutAnimation == nil
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

                rendererSurface(viewSize: geometry.size)

                // Click handling
                interactionLayer(viewSize: geometry.size)
            }
            .overlay(alignment: .topLeading) {
                if let highlighted = effectiveHighlight {
                    InfoPanel(node: highlighted.node)
                        .offset(x: 10, y: 10)
                }
            }
            .focusable()
            .focused($isTreemapFocused)
            .onMoveCommand(perform: handleMoveCommand)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Treemap visualization")
            .accessibilityChildren {
                treemapAccessibilityChildren()
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
                deletionAnimation = nil
                layoutAnimation = nil
                hoveredNode = nil
                keyboardFocusedRectID = nil
                accessibilityFocusedRectID = nil
                lastMouseLocation = nil
                lastUpdateTime = .distantPast
                buildCache(size: geometry.size)
            }
            .onChange(of: layoutRevision) { _, _ in
                buildCache(size: geometry.size, forceRendererRefresh: true)
                refreshHoveredNode(in: geometry.size)
            }
            .onChange(of: accessibilityReduceMotion) { _, _ in
                configurePulseAnimation()
            }
            .onChange(of: accessibilityFocusedRectID) { _, newValue in
                guard let newValue, activeRect(for: newValue) != nil else {
                    keyboardFocusedRectID = nil
                    return
                }

                keyboardFocusedRectID = newValue
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
        lastMouseLocation = location

        guard deletionAnimation == nil else {
            hoveredNode = nil
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= throttleInterval else { return }
        lastUpdateTime = now

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
        guard deletionAnimation == nil else {
            hoveredNode = nil
            return
        }

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

    private func buildCache(size: CGSize, forceRendererRefresh: Bool = false) {
        guard deletionAnimation == nil else { return }
        guard size.width > 0 && size.height > 0 else { return }
        lastViewSize = size

        let newRects = layoutRects(for: node, size: size)
        let newHitTestCache = makeHitTestCache(rects: newRects, size: size)
        let layoutChanged = !hasSameLayout(cachedRects, newRects)

        guard layoutChanged || forceRendererRefresh else {
            applyHitTestCache(newHitTestCache)
            layoutAnimation = nil
            animateStructuralChanges = false
            return
        }

        applyHitTestCache(newHitTestCache)
        layoutAnimation = nil
        animateStructuralChanges = layoutChanged
        rendererRevision += 1
    }

    private func layoutRects(for node: FileNode, size: CGSize) -> [TreemapRect] {
        let maxRects = min(8000, Int(size.width * size.height / 50))

        return TreemapLayout.layout(
            node: node,
            bounds: CGRect(origin: .zero, size: size),
            depth: 0,
            maxDepth: maxDepth,
            maxRects: maxRects
        )
    }

    private func makeHitTestCache(rects: [TreemapRect], size: CGSize) -> TreemapHitTestCache {
        TreemapHitTestCache(
            rects: rects,
            bounds: CGRect(origin: .zero, size: size)
        )
    }

    private func applyHitTestCache(_ cache: TreemapHitTestCache) {
        hitTestCache = cache

        if let hoveredNode, cache.rect(for: hoveredNode.id) == nil {
            self.hoveredNode = nil
        }

        if let keyboardFocusedRectID, cache.rect(for: keyboardFocusedRectID) == nil {
            self.keyboardFocusedRectID = nil
            accessibilityFocusedRectID = nil
        }
    }

    private func findHoveredNode(at point: CGPoint) -> FileNode? {
        if let layoutAnimation {
            let activeDate = Date()
            guard let motionIndex = layoutAnimation.hitTestIndex else { return nil }

            var candidateRectsByID: [UUID: TreemapRect] = [:]
            var candidates: [TreemapHitTestEntry] = []

            for candidate in motionIndex.candidates(at: point) {
                guard let rect = renderedRect(for: candidate.id, in: layoutAnimation, at: activeDate) else {
                    continue
                }

                candidateRectsByID[rect.id] = rect
                candidates.append(TreemapHitTestEntry(rect: rect))
            }

            guard let resolved = TreemapHoverResolver.resolve(point: point, candidates: candidates) else {
                return nil
            }

            return candidateRectsByID[resolved.id]?.node
        }

        return hitTestCache.hoveredRect(at: point)?.node
    }

    // MARK: - Renderer

    @ViewBuilder
    private func rendererSurface(viewSize: CGSize) -> some View {
        if deletionAnimation != nil {
            ZStack {
                mainTreemapLayer()
                hoverOverlayLayer()
            }
        } else {
            TreemapLayerSurface(
                rects: cachedRects,
                revision: rendererRevision,
                animateStructuralChanges: animateStructuralChanges,
                highlightedNodeID: highlightedNode?.id,
                hoveredNodeID: hoveredNode?.id,
                reduceMotion: accessibilityReduceMotion,
                pulseTargetID: pulseTargetRect?.id,
                shouldRenderPulse: shouldRenderPulse,
                zoomScale: effectiveZoomScale,
                zoomAnchor: effectiveZoomAnchor
            ) { location in
                handleMouseMove(location, in: viewSize)
            }
        }
    }

    @ViewBuilder
    private func mainTreemapLayer() -> some View {
        if deletionAnimation != nil || layoutAnimation != nil {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    drawTreemapStatic(context: &context, size: size, at: timeline.date)
                }
                .drawingGroup()
            }
        } else {
            Canvas { context, size in
                drawTreemapStatic(context: &context, size: size)
            }
            .drawingGroup()
        }
    }

    @ViewBuilder
    private func hoverOverlayLayer() -> some View {
        if deletionAnimation != nil || layoutAnimation != nil {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    drawHoverOverlay(context: context, size: size, at: timeline.date)
                }
            }
        } else {
            Canvas { context, size in
                drawHoverOverlay(context: context, size: size)
            }
        }
    }

    private func drawTreemapStatic(context: inout GraphicsContext, size: CGSize, at date: Date? = nil) {
        applyZoomTransform(to: &context, size: size)

        if let deletionAnimation {
            for renderedRect in renderedRects(for: deletionAnimation, at: date ?? .now) {
                drawStaticRect(
                    renderedRect.rect,
                    pulseScale: 1,
                    opacity: renderedRect.opacity,
                    context: &context
                )
            }
            return
        }

        if let layoutAnimation {
            let activeDate = date ?? .now

            for renderedRect in renderedRects(for: layoutAnimation, at: activeDate) {
                drawStaticRect(
                    renderedRect.rect,
                    pulseScale: 1,
                    opacity: renderedRect.opacity,
                    context: &context
                )
            }
            return
        }

        let pulseTargetID = pulseTargetRect?.id

        for rect in cachedRects {
            guard rect.id != pulseTargetID else { continue }
            drawStaticRect(rect, pulseScale: 1, opacity: 1, context: &context)
        }

        if let pulseTargetRect, shouldRenderPulse {
            drawStaticRect(pulseTargetRect, pulseScale: currentPulseScale, opacity: 1, context: &context)
        } else if let pulseTargetRect {
            drawStaticRect(pulseTargetRect, pulseScale: 1, opacity: 1, context: &context)
        }
    }

    private func drawStaticRect(
        _ rect: TreemapRect,
        pulseScale: CGFloat,
        opacity: Double,
        context: inout GraphicsContext
    ) {
        let padding: CGFloat = rect.depth == 0 ? 1.0 : 0.5
        let insetRect = rect.cgRect.insetBy(dx: padding, dy: padding)
        guard opacity > 0.01, insetRect.width > 0.5 && insetRect.height > 0.5 else { return }

        let cornerRadius: CGFloat = rect.depth == 0 ? 2 : 1
        let path = Path(roundedRect: insetRect, cornerRadius: cornerRadius)

        if pulseScale > 1 || opacity < 0.999 {
            context.drawLayer { layer in
                layer.opacity = opacity
                let center = CGPoint(x: insetRect.midX, y: insetRect.midY)
                if pulseScale > 1 {
                    layer.translateBy(x: center.x, y: center.y)
                    layer.scaleBy(x: pulseScale, y: pulseScale)
                    layer.translateBy(x: -center.x, y: -center.y)
                }
                drawRectFillAndBorder(rect, path: path, context: &layer)
            }
        } else {
            drawRectFillAndBorder(rect, path: path, context: &context)
        }

        if let labelLayout = rect.labelLayout {
            drawLabel(labelLayout, rect: rect, context: &context)
        }
    }

    private func drawRectFillAndBorder(_ rect: TreemapRect, path: Path, context: inout GraphicsContext) {
        let shadingStyle = TreemapColorStyling.shadingStyle(for: rect.color, depth: rect.depth)
        let gradientRect = rect.displayRect

        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [shadingStyle.gradientStartColor, shadingStyle.gradientEndColor]),
                startPoint: CGPoint(x: gradientRect.minX, y: gradientRect.minY),
                endPoint: CGPoint(x: gradientRect.maxX, y: gradientRect.maxY)
            )
        )

        if rect.depth < 2 {
            context.stroke(path, with: .color(.black.opacity(0.2)), lineWidth: 0.5)
        }
    }

    // MARK: - Hover Overlay

    private func drawHoverOverlay(context: GraphicsContext, size: CGSize, at date: Date? = nil) {
        guard let highlighted = effectiveHighlight else { return }

        let activeRects = activeRects(at: date)
        guard let highlightedRect = activeRect(for: highlighted.node.id, at: date) else { return }

        var context = context
        applyZoomTransform(to: &context, size: size)

        // Find top-level parent
        let parentRect = findTopLevelParent(of: highlightedRect, in: activeRects)

        // Dim non-parent areas
        if let parent = parentRect {
            for rect in activeRects where rect.depth == 0 && rect.id != parent.id {
                let path = Path(roundedRect: rect.cgRect.insetBy(dx: 1, dy: 1), cornerRadius: 2)
                context.fill(path, with: .color(.black.opacity(0.5)))
            }

            // Parent border
            let parentPath = Path(roundedRect: parent.cgRect.insetBy(dx: 1, dy: 1), cornerRadius: 2)
            context.stroke(parentPath, with: .color(.white.opacity(0.8)), lineWidth: 2)
        }

        let padding: CGFloat = highlightedRect.depth == 0 ? 1.0 : 0.5
        let highlightedPath = Path(roundedRect: highlightedRect.cgRect.insetBy(dx: padding, dy: padding), cornerRadius: highlightedRect.depth == 0 ? 2 : 1)

        switch highlighted.source {
        case .hover:
            context.stroke(highlightedPath, with: .color(.yellow), lineWidth: 2)
        case .keyboard:
            context.stroke(highlightedPath, with: .color(.white), lineWidth: 4)
            context.stroke(
                highlightedPath,
                with: .color(.black.opacity(0.72)),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
        case .treeSelection:
            context.stroke(highlightedPath, with: .color(.cyan), lineWidth: 2)
        }
    }

    private func activeRect(for id: UUID, at date: Date? = nil) -> TreemapRect? {
        let activeDate = date ?? .now

        if let deletionAnimation {
            return renderedRect(for: id, in: deletionAnimation, at: activeDate)
        }

        if let layoutAnimation {
            return renderedRect(for: id, in: layoutAnimation, at: activeDate)
        }

        return hitTestCache.rect(for: id)
    }

    private func activeRects(at date: Date? = nil) -> [TreemapRect] {
        if let deletionAnimation {
            return renderedRects(for: deletionAnimation, at: date ?? .now).map(\.rect)
        }

        if let layoutAnimation {
            return renderedRects(for: layoutAnimation, at: date ?? .now).map(\.rect)
        }

        return cachedRects
    }

    private func renderedRect(
        for id: UUID,
        in animation: TreemapDeletionAnimation,
        at date: Date
    ) -> TreemapRect? {
        let deletedProgress = animation.motion.deletedRectProgress(at: date.timeIntervalSince(animation.startedAt))
        let survivingProgress = animation.motion.survivingRectProgress(at: date.timeIntervalSince(animation.startedAt))

        if let sourceRect = animation.sourceRectsByID[id] {
            if animation.deletedNodeIDs.contains(sourceRect.id) {
                let collapseCenter = sourceRect.id == animation.targetRect.id
                    ? sourceRect.center
                    : animation.targetRect.center
                return collapse(rect: sourceRect, toward: collapseCenter, progress: deletedProgress)
            }

            if let destinationRect = animation.destinationRectsByID[sourceRect.id] {
                return interpolate(from: sourceRect, to: destinationRect, progress: survivingProgress)
            }

            return collapse(rect: sourceRect, toward: sourceRect.center, progress: deletedProgress)
        }

        guard let destinationRect = animation.destinationRectsByID[id] else { return nil }
        guard !animation.sourceRectIDs.contains(id) else { return nil }

        return interpolate(
            from: collapsedRect(for: destinationRect, around: animation.targetRect.center),
            to: destinationRect,
            progress: survivingProgress
        )
    }

    private func renderedRect(
        for id: UUID,
        in animation: TreemapLayoutAnimation,
        at date: Date
    ) -> TreemapRect? {
        let progress = animation.motion.progress(at: date.timeIntervalSince(animation.startedAt))

        if let sourceRect = animation.sourceRectsByID[id] {
            if let destinationRect = animation.destinationRectsByID[sourceRect.id] {
                return interpolate(from: sourceRect, to: destinationRect, progress: progress)
            }

            return collapse(rect: sourceRect, toward: sourceRect.center, progress: progress)
        }

        guard let destinationRect = animation.destinationRectsByID[id] else { return nil }
        guard !animation.sourceRectIDs.contains(id) else { return nil }

        return interpolate(
            from: collapsedRect(for: destinationRect, around: destinationRect.center),
            to: destinationRect,
            progress: progress
        )
    }

    private func renderedRects(for animation: TreemapDeletionAnimation, at date: Date) -> [RenderedTreemapRect] {
        let deletedProgress = animation.motion.deletedRectProgress(at: date.timeIntervalSince(animation.startedAt))
        let survivingProgress = animation.motion.survivingRectProgress(at: date.timeIntervalSince(animation.startedAt))
        var renderedRects: [RenderedTreemapRect] = []
        renderedRects.reserveCapacity(max(animation.sourceRects.count, animation.destinationRects.count))

        for sourceRect in animation.sourceRects {
            if animation.deletedNodeIDs.contains(sourceRect.id) {
                let collapseCenter = sourceRect.id == animation.targetRect.id
                    ? sourceRect.center
                    : animation.targetRect.center
                renderedRects.append(
                    RenderedTreemapRect(
                        rect: collapse(rect: sourceRect, toward: collapseCenter, progress: deletedProgress),
                        opacity: 1 - deletedProgress
                    )
                )
                continue
            }

            if let destinationRect = animation.destinationRectsByID[sourceRect.id] {
                renderedRects.append(
                    RenderedTreemapRect(
                        rect: interpolate(from: sourceRect, to: destinationRect, progress: survivingProgress),
                        opacity: 1
                    )
                )
            } else {
                renderedRects.append(
                    RenderedTreemapRect(
                        rect: collapse(rect: sourceRect, toward: sourceRect.center, progress: deletedProgress),
                        opacity: 1 - deletedProgress
                    )
                )
            }
        }

        for destinationRect in animation.destinationRects where !animation.sourceRectIDs.contains(destinationRect.id) {
            renderedRects.append(
                RenderedTreemapRect(
                    rect: interpolate(
                        from: collapsedRect(for: destinationRect, around: animation.targetRect.center),
                        to: destinationRect,
                        progress: survivingProgress
                    ),
                    opacity: animation.motion.appearingRectOpacity(for: date.timeIntervalSince(animation.startedAt))
                )
            )
        }

        return renderedRects
    }

    private func renderedRects(for animation: TreemapLayoutAnimation, at date: Date) -> [RenderedTreemapRect] {
        let progress = animation.motion.progress(at: date.timeIntervalSince(animation.startedAt))
        let appearingOpacity = animation.motion.appearingRectOpacity(at: date.timeIntervalSince(animation.startedAt))
        var renderedRects: [RenderedTreemapRect] = []
        renderedRects.reserveCapacity(max(animation.sourceRects.count, animation.destinationRects.count))

        for sourceRect in animation.sourceRects {
            if let destinationRect = animation.destinationRectsByID[sourceRect.id] {
                renderedRects.append(
                    RenderedTreemapRect(
                        rect: interpolate(from: sourceRect, to: destinationRect, progress: progress),
                        opacity: 1
                    )
                )
            } else {
                renderedRects.append(
                    RenderedTreemapRect(
                        rect: collapse(rect: sourceRect, toward: sourceRect.center, progress: progress),
                        opacity: 1 - progress
                    )
                )
            }
        }

        for destinationRect in animation.destinationRects where !animation.sourceRectIDs.contains(destinationRect.id) {
            renderedRects.append(
                RenderedTreemapRect(
                    rect: interpolate(
                        from: collapsedRect(for: destinationRect, around: destinationRect.center),
                        to: destinationRect,
                        progress: progress
                    ),
                    opacity: appearingOpacity
                )
            )
        }

        return renderedRects
    }

    private func interpolate(from start: TreemapRect, to end: TreemapRect, progress: Double) -> TreemapRect {
        let x = start.x + (end.x - start.x) * progress
        let y = start.y + (end.y - start.y) * progress
        let width = start.width + (end.width - start.width) * progress
        let height = start.height + (end.height - start.height) * progress

        return TreemapRect(
            id: end.id,
            x: x,
            y: y,
            width: max(0, width),
            height: max(0, height),
            node: end.node,
            depth: end.depth,
            color: end.color
        )
    }

    private func collapse(rect: TreemapRect, toward center: CGPoint, progress: Double) -> TreemapRect {
        let scale = max(0, 1 - progress)
        let interpolatedCenter = CGPoint(
            x: rect.center.x + (center.x - rect.center.x) * progress,
            y: rect.center.y + (center.y - rect.center.y) * progress
        )

        return TreemapRect(
            id: rect.id,
            x: Double(interpolatedCenter.x) - rect.width * scale / 2,
            y: Double(interpolatedCenter.y) - rect.height * scale / 2,
            width: rect.width * scale,
            height: rect.height * scale,
            node: rect.node,
            depth: rect.depth,
            color: rect.color
        )
    }

    private func collapsedRect(for rect: TreemapRect, around center: CGPoint) -> TreemapRect {
        TreemapRect(
            id: rect.id,
            x: center.x,
            y: center.y,
            width: 0,
            height: 0,
            node: rect.node,
            depth: rect.depth,
            color: rect.color
        )
    }

    private func startLayoutAnimation(from sourceRects: [TreemapRect], to destinationRects: [TreemapRect]) {
        guard !sourceRects.isEmpty || !destinationRects.isEmpty else {
            layoutAnimation = nil
            return
        }

        let animation = TreemapLayoutAnimation(
            sourceRects: sourceRects,
            destinationRects: destinationRects,
            startedAt: .now,
            reduceMotion: accessibilityReduceMotion
        )

        layoutAnimation = animation
        scheduleLayoutAnimationCompletion(for: animation)
    }

    private func scheduleLayoutAnimationCompletion(for animation: TreemapLayoutAnimation) {
        DispatchQueue.main.asyncAfter(deadline: .now() + animation.motion.duration) {
            guard layoutAnimation?.token == animation.token else { return }

            applyHitTestCache(makeHitTestCache(rects: animation.destinationRects, size: lastViewSize))
            layoutAnimation = nil
            refreshHoveredNode(in: lastViewSize)
        }
    }

    private func hasSameLayout(_ lhs: [TreemapRect], _ rhs: [TreemapRect]) -> Bool {
        guard lhs.count == rhs.count else { return false }

        return zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id &&
            abs(left.x - right.x) < 0.001 &&
            abs(left.y - right.y) < 0.001 &&
            abs(left.width - right.width) < 0.001 &&
            abs(left.height - right.height) < 0.001
        }
    }

    private func applyZoomTransform(to context: inout GraphicsContext, size: CGSize) {
        let scale = effectiveZoomScale
        guard abs(scale - 1) > 0.0001 else { return }

        let anchorPoint = VisualizationZoomState.anchorPoint(for: effectiveZoomAnchor, in: size)
        context.translateBy(x: anchorPoint.x, y: anchorPoint.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -anchorPoint.x, y: -anchorPoint.y)
    }

    private func findTopLevelParent(of rect: TreemapRect, in rects: [TreemapRect]) -> TreemapRect? {
        if rect.depth == 0 { return rect }
        return rects.first { $0.depth == 0 && $0.contains(rect.center) }
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
        guard deletionAnimation == nil, !incrementalScanInProgress else { return }
        isTreemapFocused = true

        if let hoveredNode, hoveredNode.isDirectory {
            onSelect(hoveredNode)
        }
    }

    private func handleResetTap() {
        guard deletionAnimation == nil else { return }
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
    private func interactionLayer(viewSize: CGSize) -> some View {
        let surface = Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                handlePrimaryTap()
            }
            .contextMenu {
                contextMenuItems(viewSize: viewSize)
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

    @ViewBuilder
    private func contextMenuItems(viewSize: CGSize) -> some View {
        if deletionAnimation != nil {
            Label("Deletion In Progress", systemImage: "hourglass")
        } else if incrementalScanInProgress {
            Label("Scan In Progress", systemImage: "hourglass")

            Text("Navigation and file actions unlock after completion")
        } else if let hoveredNode {
            Button(role: .destructive) {
                beginAnimatedTrash(for: hoveredNode, in: viewSize)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) {} label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(true)

            Text("Hover a file or folder first")
        }
    }

    private func beginAnimatedTrash(for target: FileNode, in viewSize: CGSize) {
        guard !incrementalScanInProgress else { return }
        hoveredNode = nil
        lastMouseLocation = nil
        onMoveToTrash(target)
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard deletionAnimation == nil else { return }
        guard let direction = VisualizationKeyboardDirection(direction) else { return }
        guard !treemapAccessibilityNodes.isEmpty else { return }

        let currentID = keyboardFocusedRectID
            ?? hoveredNode?.id
            ?? highlightedNode?.id
            ?? treemapAccessibilityNodes.first(where: { $0.depth == 0 })?.id
            ?? treemapAccessibilityNodes.first?.id

        guard let currentID else { return }

        let nextID = TreemapAccessibilityNavigation.nextID(
            from: currentID,
            in: treemapAccessibilityNodes,
            direction: direction
        ) ?? currentID

        setKeyboardFocus(to: nextID)
    }

    private func setKeyboardFocus(to rectID: UUID?) {
        guard let rectID, activeRect(for: rectID) != nil else {
            keyboardFocusedRectID = nil
            accessibilityFocusedRectID = nil
            return
        }

        keyboardFocusedRectID = rectID
        accessibilityFocusedRectID = rectID
    }

    private func accessibilityValue(for rect: TreemapRect) -> String {
        VisualizationAccessibilityFormatter.treemapValue(
            sizeText: rect.node.formattedSize,
            part: rect.node.size,
            parent: rect.parentSize
        )
    }

    private func activateTreemapNode(_ node: FileNode) {
        guard node.isDirectory, !incrementalScanInProgress, deletionAnimation == nil else {
            return
        }

        onSelect(node)
    }

    @ViewBuilder
    private func treemapAccessibilityChildren() -> some View {
        ForEach(cachedRects) { rect in
            treemapAccessibilityProxy(for: rect)
        }
    }

    @ViewBuilder
    private func treemapAccessibilityProxy(for rect: TreemapRect) -> some View {
        let proxy = Color.clear
            .frame(
                width: max(rect.displayRect.width, 1),
                height: max(rect.displayRect.height, 1)
            )
            .position(x: rect.displayRect.midX, y: rect.displayRect.midY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rect.node.name)
            .accessibilityValue(accessibilityValue(for: rect))
            .accessibilityFocused($accessibilityFocusedRectID, equals: rect.id)

        if rect.node.isDirectory {
            proxy
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: Text("Open folder")) {
                    activateTreemapNode(rect.node)
                }
        } else {
            proxy
        }
    }

    private func isAnimatingRemoval(for node: FileNode) -> Bool {
        deletionAnimation?.targetNode.containsNode(withID: node.id) == true
    }

    // MARK: - Labels

    private func drawLabel(_ layout: TreemapLabelLayout, rect: TreemapRect, context: inout GraphicsContext) {
        drawShadowedText(
            Text(layout.displayName)
                .font(.system(size: layout.fontSize, weight: .medium))
                .foregroundColor(.white),
            at: CGPoint(
                x: layout.nameFrame.minX,
                y: layout.nameFrame.minY + layout.fontSize / 2
            ),
            context: &context
        )

        if let sizeFrame = layout.sizeFrame {
            drawShadowedText(
                Text(rect.node.formattedSize)
                    .font(.system(size: layout.fontSize - 1))
                    .foregroundColor(.white.opacity(0.8)),
                at: CGPoint(
                    x: sizeFrame.minX,
                    y: sizeFrame.minY + max(layout.fontSize - 1, 8) / 2
                ),
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

private struct RenderedTreemapRect {
    let rect: TreemapRect
    let opacity: Double
}

private enum TreemapHighlightSource {
    case hover
    case keyboard
    case treeSelection
}

private struct TreemapHighlightState {
    let node: FileNode
    let source: TreemapHighlightSource
}

private struct TreemapDeletionAnimation {
    let token = UUID()
    let targetNode: FileNode
    let targetRect: TreemapRect
    let sourceRects: [TreemapRect]
    let sourceRectsByID: [UUID: TreemapRect]
    let sourceRectIDs: Set<UUID>
    let destinationRects: [TreemapRect]
    let destinationRectsByID: [UUID: TreemapRect]
    let deletedNodeIDs: Set<UUID>
    let startedAt: Date
    let motion: TreemapDeletionMotionPolicy

    init(
        targetNode: FileNode,
        targetRect: TreemapRect,
        sourceRects: [TreemapRect],
        destinationRects: [TreemapRect],
        startedAt: Date,
        reduceMotion: Bool
    ) {
        self.targetNode = targetNode
        self.targetRect = targetRect
        self.sourceRects = sourceRects
        self.sourceRectsByID = Dictionary(uniqueKeysWithValues: sourceRects.map { ($0.id, $0) })
        self.sourceRectIDs = Set(sourceRects.map(\.id))
        self.destinationRects = destinationRects
        self.destinationRectsByID = Dictionary(uniqueKeysWithValues: destinationRects.map { ($0.id, $0) })
        self.deletedNodeIDs = Set(sourceRects.map(\.id).filter { targetNode.containsNode(withID: $0) })
        self.startedAt = startedAt
        self.motion = TreemapDeletionMotionPolicy(reduceMotion: reduceMotion)
    }
}

private struct TreemapLayoutAnimation {
    let token = UUID()
    let sourceRects: [TreemapRect]
    let sourceRectsByID: [UUID: TreemapRect]
    let sourceRectIDs: Set<UUID>
    let destinationRects: [TreemapRect]
    let destinationRectsByID: [UUID: TreemapRect]
    let hitTestIndex: TreemapSpatialIndex?
    let startedAt: Date
    let motion: TreemapLayoutMotionPolicy

    init(
        sourceRects: [TreemapRect],
        destinationRects: [TreemapRect],
        startedAt: Date,
        reduceMotion: Bool
    ) {
        self.sourceRects = sourceRects
        self.sourceRectsByID = Dictionary(uniqueKeysWithValues: sourceRects.map { ($0.id, $0) })
        self.sourceRectIDs = Set(sourceRects.map(\.id))
        self.destinationRects = destinationRects
        self.destinationRectsByID = Dictionary(uniqueKeysWithValues: destinationRects.map { ($0.id, $0) })
        self.hitTestIndex = TreemapLayoutAnimation.makeHitTestIndex(
            sourceRects: sourceRects,
            destinationRects: destinationRects
        )
        self.startedAt = startedAt
        self.motion = TreemapLayoutMotionPolicy(reduceMotion: reduceMotion)
    }

    private static func makeHitTestIndex(
        sourceRects: [TreemapRect],
        destinationRects: [TreemapRect]
    ) -> TreemapSpatialIndex? {
        let sourceRectsByID = Dictionary(uniqueKeysWithValues: sourceRects.map { ($0.id, $0) })
        let destinationRectsByID = Dictionary(uniqueKeysWithValues: destinationRects.map { ($0.id, $0) })
        let allIDs = Set(sourceRectsByID.keys).union(destinationRectsByID.keys)

        var entries: [TreemapHitTestEntry] = []
        entries.reserveCapacity(allIDs.count)

        var bounds = CGRect.null

        for id in allIDs {
            guard let entry = motionEnvelopeEntry(
                source: sourceRectsByID[id],
                destination: destinationRectsByID[id]
            ) else {
                continue
            }

            guard entry.isIndexable else { continue }

            bounds = bounds.isNull ? entry.rect : bounds.union(entry.rect)
            entries.append(entry)
        }

        guard !entries.isEmpty, !bounds.isNull else { return nil }

        var index = TreemapSpatialIndex(bounds: bounds)
        for entry in entries {
            index.insert(entry)
        }

        return index
    }

    private static func motionEnvelopeEntry(
        source: TreemapRect?,
        destination: TreemapRect?
    ) -> TreemapHitTestEntry? {
        switch (source, destination) {
        case let (.some(sourceRect), .some(destinationRect)):
            let envelope = sourceRect.cgRect.union(destinationRect.cgRect)
            return TreemapHitTestEntry(
                id: destinationRect.id,
                rect: envelope,
                depth: max(sourceRect.depth, destinationRect.depth)
            )
        case let (.some(sourceRect), .none):
            return TreemapHitTestEntry(rect: sourceRect)
        case let (.none, .some(destinationRect)):
            return TreemapHitTestEntry(rect: destinationRect)
        case (.none, .none):
            return nil
        }
    }
}

private struct TreemapDeletionMotionPolicy {
    let reduceMotion: Bool

    var collapseDuration: TimeInterval {
        reduceMotion ? 0.18 : 0.3
    }

    var totalDuration: TimeInterval {
        reduceMotion ? 0.22 : 0.42
    }

    func deletedRectProgress(at elapsed: TimeInterval) -> Double {
        let t = normalized(elapsed, over: collapseDuration)
        return reduceMotion ? easeOut(t) : easeIn(t)
    }

    func survivingRectProgress(at elapsed: TimeInterval) -> Double {
        let t = normalized(elapsed, over: totalDuration)
        let eased = easeOut(t)

        guard !reduceMotion else { return eased }

        let overshoot = sin(t * .pi) * (1 - t) * 0.06
        return min(max(eased + overshoot, 0), 1.04)
    }

    func appearingRectOpacity(for elapsed: TimeInterval) -> Double {
        min(1, survivingRectProgress(at: elapsed))
    }

    private func normalized(_ elapsed: TimeInterval, over duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(elapsed / duration, 0), 1)
    }

    private func easeIn(_ t: Double) -> Double {
        t * t * t
    }

    private func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }
}

private struct TreemapLayoutMotionPolicy {
    let reduceMotion: Bool

    var duration: TimeInterval {
        reduceMotion ? 0.12 : 0.24
    }

    func progress(at elapsed: TimeInterval) -> Double {
        let t = normalized(elapsed, over: duration)

        if reduceMotion {
            return easeOut(t)
        }

        return easeInOut(t)
    }

    func appearingRectOpacity(at elapsed: TimeInterval) -> Double {
        min(1, progress(at: elapsed))
    }

    private func normalized(_ elapsed: TimeInterval, over duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(elapsed / duration, 0), 1)
    }

    private func easeOut(_ t: Double) -> Double {
        1 - pow(1 - t, 3)
    }

    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
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
    TreemapView(
        node: FileNode(url: URL(fileURLWithPath: "/"), isDirectory: true),
        highlightedNode: nil,
        onSelect: { _ in },
        layoutRevision: 0,
        incrementalScanInProgress: false,
        onMoveToTrash: { _ in }
    )
    .frame(width: 600, height: 400)
}
