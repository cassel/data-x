import SwiftUI
import AppKit

struct TreemapView: View {
    let node: FileNode
    let highlightedNode: FileNode?  // From file tree selection
    let onSelect: (FileNode) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var cachedRects: [TreemapRect] = []
    @State private var hoveredNode: FileNode?
    @State private var lastUpdateTime: Date = .distantPast
    @State private var pulseExpanded = false

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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                // Static treemap layer - rasterized for performance
                Canvas { context, _ in
                    drawTreemapStatic(context: &context)
                }
                .drawingGroup()

                // Hover overlay - lightweight
                Canvas { context, _ in
                    drawHoverOverlay(context: context)
                }

                // Click handling
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let hovered = hoveredNode, hovered.isDirectory {
                            onSelect(hovered)
                        }
                    }
            }
            .background(
                MouseTracker { location in
                    handleMouseMove(location)
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
            }
            .onChange(of: node.id) { _, _ in
                buildCache(size: geometry.size)
            }
            .onChange(of: accessibilityReduceMotion) { _, _ in
                configurePulseAnimation()
            }
        }
    }

    // MARK: - Mouse Handling

    private func handleMouseMove(_ location: CGPoint?) {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= throttleInterval else { return }
        lastUpdateTime = now

        if let loc = location {
            hoveredNode = findHoveredNode(at: loc)
        } else {
            hoveredNode = nil
        }
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

    private func drawTreemapStatic(context: inout GraphicsContext) {
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

    private func drawHoverOverlay(context: GraphicsContext) {
        guard let highlighted = effectiveHighlight else { return }
        guard let highlightedRect = cachedRects.first(where: { $0.node.id == highlighted.id }) else { return }

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
