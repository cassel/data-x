import AppKit
import SwiftUI

struct SunburstView: View {
    let node: FileNode
    let onSelect: (FileNode) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var hoveredNode: FileNode?
    @State private var drillTransform = SunburstChartTransform.identity
    @State private var pendingNavigation: PendingSunburstNavigation?
    @State private var isDrillNavigating = false
    @State private var zoomState = VisualizationZoomState()
    @GestureState private var zoomGesture = VisualizationZoomGestureState()

    private let maxDepth = 4
    private let innerRadius: CGFloat = 60

    struct ArcData: Identifiable {
        let id: UUID
        let node: FileNode
        let startAngle: Double
        let endAngle: Double
        let innerRadius: CGFloat
        let outerRadius: CGFloat
        let depth: Int

        init(
            node: FileNode,
            startAngle: Double,
            endAngle: Double,
            innerRadius: CGFloat,
            outerRadius: CGFloat,
            depth: Int
        ) {
            self.id = node.id
            self.node = node
            self.startAngle = startAngle
            self.endAngle = endAngle
            self.innerRadius = innerRadius
            self.outerRadius = outerRadius
            self.depth = depth
        }
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

    private var shouldPreferResetDoubleTap: Bool {
        VisualizationZoomState.prefersResetDoubleTap(totalScale: effectiveZoomScale)
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
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = min(geometry.size.width, geometry.size.height) / 2 - 20
            let arcData = maxRadius > innerRadius ? arcs(for: node, maxRadius: maxRadius) : []

            interactiveContent(
                arcs: arcData,
                center: center,
                viewSize: geometry.size
            )
            .onChange(of: node.id) { _, newNodeID in
                handleNodeChange(newNodeID: newNodeID)
            }
            .onDisappear {
                resetDrillTransition()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func handleNodeChange(newNodeID: UUID) {
        hoveredNode = nil
        resetZoom(animated: false)

        guard let pendingNavigation,
              pendingNavigation.targetNodeID == newNodeID else {
            resetDrillTransition()
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drillTransform = pendingNavigation.plan.arrival
        }

        withAnimation(drillArrivalAnimation(for: pendingNavigation.plan)) {
            drillTransform = .identity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + pendingNavigation.plan.arrivalDuration) {
            guard self.pendingNavigation?.targetNodeID == newNodeID else { return }
            resetDrillTransition()
        }
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

    private func resetDrillTransition() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            drillTransform = .identity
        }
        pendingNavigation = nil
        isDrillNavigating = false
    }

    private func handleResetTap() {
        guard shouldPreferResetDoubleTap else { return }
        resetZoom(animated: true)
    }

    private func beginDrillDown(on arc: ArcData, in viewSize: CGSize) {
        guard arc.node.isDirectory, !isDrillNavigating else { return }

        let plan = SunburstDrillMotionPolicy.plan(
            for: arc,
            in: viewSize,
            reduceMotion: accessibilityReduceMotion
        )
        pendingNavigation = PendingSunburstNavigation(
            targetNodeID: arc.node.id,
            plan: plan
        )
        isDrillNavigating = true
        hoveredNode = nil

        withAnimation(drillDepartureAnimation(for: plan)) {
            drillTransform = plan.departure
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + plan.departureDuration) {
            guard self.pendingNavigation?.targetNodeID == arc.node.id else { return }
            onSelect(arc.node)
        }
    }

    @ViewBuilder
    private func interactiveContent(
        arcs: [ArcData],
        center: CGPoint,
        viewSize: CGSize
    ) -> some View {
        let content = ZStack {
            ForEach(arcs) { arc in
                arcView(arc, center: center, viewSize: viewSize)
            }

            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: innerRadius * 2, height: innerRadius * 2)
                .position(center)

            VStack(spacing: 4) {
                Text(node.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(node.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: innerRadius * 1.8)
            .position(center)
        }
        .contentShape(Rectangle())
        .scaleEffect(drillTransform.scale, anchor: drillTransform.anchor)
        .rotationEffect(.radians(drillTransform.rotation))
        .opacity(drillTransform.opacity)
        .scaleEffect(effectiveZoomScale, anchor: effectiveZoomAnchor)
        .overlay(alignment: .topLeading) {
            if let hoveredNode {
                SunburstHoverOverlay(
                    rootNode: node,
                    hoveredNode: hoveredNode
                )
                .padding()
            }
        }
        .simultaneousGesture(magnifyGesture)

        if shouldPreferResetDoubleTap {
            content.highPriorityGesture(
                TapGesture(count: 2)
                    .onEnded(handleResetTap),
                including: .all
            )
        } else {
            content
        }
    }

    @ViewBuilder
    private func arcView(_ arc: ArcData, center: CGPoint, viewSize: CGSize) -> some View {
        let content = ZStack {
            SunburstArc(
                arc: arc,
                center: center,
                isHovered: hoveredNode?.id == arc.node.id
            )

            if let layout = SunburstLabelPolicy.makeLayout(for: arc, center: center) {
                SunburstArcLabel(layout: layout)
                    .allowsHitTesting(false)
            }
        }
        .onHover { isHovered in
            guard !isDrillNavigating else {
                hoveredNode = nil
                return
            }

            hoveredNode = isHovered ? arc.node : nil
        }

        if shouldPreferResetDoubleTap {
            content
        } else {
            content.onTapGesture(count: 2) {
                beginDrillDown(on: arc, in: viewSize)
            }
        }
    }

    private func arcs(for rootNode: FileNode, maxRadius: CGFloat) -> [ArcData] {
        var result: [ArcData] = []
        let ringWidth = (maxRadius - innerRadius) / CGFloat(maxDepth)

        func processNode(_ node: FileNode, startAngle: Double, endAngle: Double, depth: Int) {
            guard depth < maxDepth else { return }
            guard let children = node.sortedChildren, !children.isEmpty else { return }

            let totalSize = Double(children.reduce(0) { $0 + $1.size })
            guard totalSize > 0 else { return }

            var currentAngle = startAngle

            for child in children {
                let angleSpan = (Double(child.size) / totalSize) * (endAngle - startAngle)
                let childEndAngle = currentAngle + angleSpan

                if angleSpan > 0.5 * .pi / 180 {
                    let arc = ArcData(
                        node: child,
                        startAngle: currentAngle,
                        endAngle: childEndAngle,
                        innerRadius: innerRadius + CGFloat(depth) * ringWidth,
                        outerRadius: innerRadius + CGFloat(depth + 1) * ringWidth - 1,
                        depth: depth
                    )
                    result.append(arc)

                    if child.isDirectory {
                        processNode(
                            child,
                            startAngle: currentAngle,
                            endAngle: childEndAngle,
                            depth: depth + 1
                        )
                    }
                }

                currentAngle = childEndAngle
            }
        }

        processNode(rootNode, startAngle: 0, endAngle: 2 * .pi, depth: 0)
        return result
    }

    private func drillDepartureAnimation(for plan: SunburstDrillMotionPlan) -> Animation {
        if accessibilityReduceMotion {
            return .easeOut(duration: plan.departureDuration)
        }

        return .easeInOut(duration: plan.departureDuration)
    }

    private func drillArrivalAnimation(for plan: SunburstDrillMotionPlan) -> Animation {
        if accessibilityReduceMotion {
            return .easeOut(duration: plan.arrivalDuration)
        }

        return .spring(
            response: plan.arrivalDuration,
            dampingFraction: 0.86,
            blendDuration: 0.12
        )
    }
}

private struct PendingSunburstNavigation {
    let targetNodeID: UUID
    let plan: SunburstDrillMotionPlan
}

struct SunburstChartTransform {
    let scale: CGFloat
    let rotation: Double
    let opacity: Double
    let anchor: UnitPoint

    static let identity = SunburstChartTransform(
        scale: 1,
        rotation: 0,
        opacity: 1,
        anchor: .center
    )
}

struct SunburstDrillMotionPlan {
    let departure: SunburstChartTransform
    let arrival: SunburstChartTransform
    let departureDuration: Double
    let arrivalDuration: Double
}

enum SunburstDrillMotionPolicy {
    static func plan(
        for arc: SunburstView.ArcData,
        in size: CGSize,
        reduceMotion: Bool
    ) -> SunburstDrillMotionPlan {
        let anchor = anchor(for: arc, in: size)
        let focusRotation = focusRotation(for: arc)

        if reduceMotion {
            return SunburstDrillMotionPlan(
                departure: SunburstChartTransform(
                    scale: 0.985,
                    rotation: 0,
                    opacity: 0.94,
                    anchor: anchor
                ),
                arrival: SunburstChartTransform(
                    scale: 1.02,
                    rotation: 0,
                    opacity: 0.96,
                    anchor: anchor
                ),
                departureDuration: 0.08,
                arrivalDuration: 0.14
            )
        }

        return SunburstDrillMotionPlan(
            departure: SunburstChartTransform(
                scale: 0.93,
                rotation: focusRotation * 0.55,
                opacity: 0.9,
                anchor: anchor
            ),
            arrival: SunburstChartTransform(
                scale: 1.12,
                rotation: focusRotation,
                opacity: 0.76,
                anchor: anchor
            ),
            departureDuration: 0.12,
            arrivalDuration: 0.28
        )
    }

    private static func anchor(for arc: SunburstView.ArcData, in size: CGSize) -> UnitPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let point = arc.point(center: center)
        let x = (point.x / max(size.width, 1)).clamped(to: 0.12 ... 0.88)
        let y = (point.y / max(size.height, 1)).clamped(to: 0.12 ... 0.88)
        return UnitPoint(x: x, y: y)
    }

    private static func focusRotation(for arc: SunburstView.ArcData) -> Double {
        let signedMidAngle = atan2(sin(arc.midAngle), cos(arc.midAngle))
        return (-signedMidAngle * 0.55).clamped(to: -0.4 ... 0.4)
    }
}

struct SunburstArcLabelLayout {
    let name: String
    let sizeText: String?
    let fontSize: CGFloat
    let sizeFontSize: CGFloat
    let position: CGPoint
    let rotation: Angle
    let maxTextWidth: CGFloat
}

enum SunburstLabelPolicy {
    private static let minimumAngleSpan = 0.22
    private static let tangentialPadding: CGFloat = 14
    private static let radialPadding: CGFloat = 8
    private static let sizeLineSpacing: CGFloat = 3

    static func makeLayout(
        for arc: SunburstView.ArcData,
        center: CGPoint = .zero
    ) -> SunburstArcLabelLayout? {
        let angleSpan = arc.angleSpan
        let ringThickness = arc.ringThickness
        let arcLength = arc.midRadius * angleSpan

        guard angleSpan >= minimumAngleSpan else { return nil }
        guard ringThickness >= 20 else { return nil }
        guard arc.innerRadius >= 64 else { return nil }

        let availableWidth = arcLength - tangentialPadding
        let availableHeight = ringThickness - radialPadding
        guard availableWidth >= 48, availableHeight >= 14 else { return nil }

        let fontSize = min(max(10, ringThickness * 0.28), 13)
        let sizeFontSize = max(8, fontSize - 1)
        let nameFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let sizeFont = NSFont.monospacedSystemFont(ofSize: sizeFontSize, weight: .regular)
        let nameHeight = ceil(nameFont.ascender - nameFont.descender) + 2
        let sizeHeight = ceil(sizeFont.ascender - sizeFont.descender) + 2
        let nameWidth = measuredWidth(of: arc.node.name, using: nameFont)

        guard nameWidth <= availableWidth, nameHeight <= availableHeight else { return nil }

        let sizeText = arc.node.formattedSize
        let sizeWidth = measuredWidth(of: sizeText, using: sizeFont)
        let canFitSize = availableHeight >= nameHeight + sizeLineSpacing + sizeHeight
            && max(nameWidth, sizeWidth) <= availableWidth
            && angleSpan >= 0.34

        return SunburstArcLabelLayout(
            name: arc.node.name,
            sizeText: canFitSize ? sizeText : nil,
            fontSize: fontSize,
            sizeFontSize: sizeFontSize,
            position: arc.point(center: center),
            rotation: .radians(arc.labelRotation),
            maxTextWidth: availableWidth
        )
    }

    private static func measuredWidth(of text: String, using font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

private extension SunburstView.ArcData {
    var angleSpan: Double {
        endAngle - startAngle
    }

    var midAngle: Double {
        (startAngle + endAngle) / 2
    }

    var midRadius: CGFloat {
        (innerRadius + outerRadius) / 2
    }

    var ringThickness: CGFloat {
        outerRadius - innerRadius
    }

    var labelRotation: Double {
        let baseRotation = midAngle
        return shouldFlipLabel ? baseRotation + .pi : baseRotation
    }

    var shouldFlipLabel: Bool {
        midAngle > .pi / 2 && midAngle < 3 * .pi / 2
    }

    func point(center: CGPoint) -> CGPoint {
        point(center: center, radius: midRadius)
    }

    func point(center: CGPoint, radius: CGFloat) -> CGPoint {
        let drawingAngle = midAngle - .pi / 2
        return CGPoint(
            x: center.x + CGFloat(cos(drawingAngle)) * radius,
            y: center.y + CGFloat(sin(drawingAngle)) * radius
        )
    }

    func path(center: CGPoint) -> Path {
        Path { path in
            path.addArc(
                center: center,
                radius: outerRadius,
                startAngle: .radians(startAngle - .pi / 2),
                endAngle: .radians(endAngle - .pi / 2),
                clockwise: false
            )
            path.addArc(
                center: center,
                radius: innerRadius,
                startAngle: .radians(endAngle - .pi / 2),
                endAngle: .radians(startAngle - .pi / 2),
                clockwise: true
            )
            path.closeSubpath()
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private struct SunburstHoverOverlay: View {
    let rootNode: FileNode
    let hoveredNode: FileNode

    private var breadcrumbPath: [FileNode] {
        FileNodePathResolver.path(from: rootNode, to: hoveredNode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SunburstInfoPanel(node: hoveredNode)
            SunburstBreadcrumbTrail(path: breadcrumbPath)
        }
    }
}

private struct SunburstBreadcrumbTrail: View {
    let path: [FileNode]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, pathNode in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        if index == 0 {
                            Image(systemName: "house.fill")
                                .font(.caption2)
                        }

                        Text(pathNode.name)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundColor(.primary)
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SunburstArcLabel: View {
    let layout: SunburstArcLabelLayout

    var body: some View {
        VStack(spacing: layout.sizeText == nil ? 0 : 2) {
            Text(layout.name)
                .font(.system(size: layout.fontSize, weight: .semibold))
                .lineLimit(1)

            if let sizeText = layout.sizeText {
                Text(sizeText)
                    .font(.system(size: layout.sizeFontSize, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.28), radius: 1.2, y: 1)
        .frame(width: layout.maxTextWidth)
        .multilineTextAlignment(.center)
        .rotationEffect(layout.rotation)
        .position(layout.position)
    }
}

struct SunburstArc: View {
    let arc: SunburstView.ArcData
    let center: CGPoint
    let isHovered: Bool

    var body: some View {
        let path = arc.path(center: center)

        path
            .fill(arcColor)
            .overlay {
                path.stroke(
                    isHovered ? Color.white : Color.white.opacity(0.3),
                    lineWidth: isHovered ? 2 : 0.5
                )
            }
    }

    private var arcColor: Color {
        let baseColor = arc.node.isDirectory
            ? FileCategory.folders.color
            : arc.node.category.color

        let depthFactor = 1.0 - Double(arc.depth) * 0.15
        return isHovered
            ? baseColor.opacity(0.9)
            : baseColor.opacity(depthFactor)
    }
}

struct SunburstInfoPanel: View {
    let node: FileNode

    private var itemCountText: String {
        let itemLabel = node.fileCount == 1 ? "item" : "items"
        return "\(node.fileCount) \(itemLabel)"
    }

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
                Text(itemCountText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    let root = FileNode(url: URL(fileURLWithPath: "/test"), isDirectory: true)
    SunburstView(node: root) { _ in }
        .frame(width: 500, height: 500)
}
