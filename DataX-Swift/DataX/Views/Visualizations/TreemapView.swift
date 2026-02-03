import SwiftUI
import AppKit

struct TreemapView: View {
    let node: FileNode
    let highlightedNode: FileNode?  // From file tree selection
    let onSelect: (FileNode) -> Void

    @State private var cachedRects: [TreemapRect] = []
    @State private var hoveredNode: FileNode?
    @State private var lastUpdateTime: Date = .distantPast

    private let maxDepth = 6
    private let throttleInterval: TimeInterval = 0.016 // ~60fps

    // Combined: hover takes priority, otherwise use highlighted from tree
    private var effectiveHighlight: FileNode? {
        hoveredNode ?? highlightedNode
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                // Static treemap layer - rasterized for performance
                Canvas { context, _ in
                    drawTreemapStatic(context: context)
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
            }
            .onChange(of: geometry.size) { _, newSize in
                buildCache(size: newSize)
            }
            .onChange(of: node.id) { _, _ in
                buildCache(size: geometry.size)
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

    private func drawTreemapStatic(context: GraphicsContext) {
        for rect in cachedRects {
            let padding: CGFloat = rect.depth == 0 ? 1.0 : 0.5
            let insetRect = rect.cgRect.insetBy(dx: padding, dy: padding)
            guard insetRect.width > 0.5 && insetRect.height > 0.5 else { continue }

            let cornerRadius: CGFloat = rect.depth == 0 ? 2 : 1
            let path = Path(roundedRect: insetRect, cornerRadius: cornerRadius)

            // Use pre-computed color
            context.fill(path, with: .color(rect.color))

            // Border for depth 0-1
            if rect.depth < 2 {
                context.stroke(path, with: .color(.black.opacity(0.2)), lineWidth: 0.5)
            }

            // Labels for depth 0
            if rect.depth == 0 && insetRect.width > 50 && insetRect.height > 25 {
                drawLabel(rect, context: context, insetRect: insetRect)
            }
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

    // MARK: - Labels

    private func drawLabel(_ rect: TreemapRect, context: GraphicsContext, insetRect: CGRect) {
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

        context.draw(
            Text(name).font(.system(size: fontSize, weight: .medium)).foregroundColor(.white),
            at: CGPoint(x: insetRect.minX + padding, y: insetRect.minY + padding + fontSize/2),
            anchor: .leading
        )

        if h > 30 {
            context.draw(
                Text(rect.node.formattedSize).font(.system(size: fontSize - 1)).foregroundColor(.white.opacity(0.8)),
                at: CGPoint(x: insetRect.minX + padding, y: insetRect.minY + padding + fontSize + 8),
                anchor: .leading
            )
        }
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
