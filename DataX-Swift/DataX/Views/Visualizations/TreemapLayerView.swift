import AppKit
import QuartzCore
import SwiftUI

enum TreemapOverlayHighlightStyle: Equatable {
    case hover
    case treeSelection
}

struct TreemapOverlayPlan: Equatable {
    let highlightRectID: UUID?
    let parentRectID: UUID?
    let dimmedTopLevelRectIDs: [UUID]
    let highlightStyle: TreemapOverlayHighlightStyle?

    static let empty = TreemapOverlayPlan(
        highlightRectID: nil,
        parentRectID: nil,
        dimmedTopLevelRectIDs: [],
        highlightStyle: nil
    )

    static func make(
        rects: [TreemapRect],
        highlightedNodeID: UUID?,
        hoveredNodeID: UUID?
    ) -> TreemapOverlayPlan {
        make(
            rectsByID: Dictionary(uniqueKeysWithValues: rects.map { ($0.id, $0) }),
            topLevelRects: rects.filter { $0.depth == 0 },
            highlightedNodeID: highlightedNodeID,
            hoveredNodeID: hoveredNodeID
        )
    }

    static func make(
        rectsByID: [UUID: TreemapRect],
        topLevelRects: [TreemapRect],
        highlightedNodeID: UUID?,
        hoveredNodeID: UUID?
    ) -> TreemapOverlayPlan {
        let activeID = hoveredNodeID ?? highlightedNodeID
        guard let activeID, let highlightedRect = rectsByID[activeID] else {
            return .empty
        }

        let parentRect: TreemapRect?
        if highlightedRect.depth == 0 {
            parentRect = highlightedRect
        } else {
            parentRect = topLevelRects.first { $0.contains(highlightedRect.center) }
        }

        return TreemapOverlayPlan(
            highlightRectID: highlightedRect.id,
            parentRectID: parentRect?.id,
            dimmedTopLevelRectIDs: topLevelRects
                .map(\.id)
                .filter { $0 != parentRect?.id },
            highlightStyle: hoveredNodeID != nil ? .hover : .treeSelection
        )
    }
}

struct TreemapLayerDiffPlan: Equatable {
    let retainedIDs: [UUID]
    let insertedIDs: [UUID]
    let removedIDs: [UUID]

    static func make(existingIDs: [UUID], nextRects: [TreemapRect]) -> TreemapLayerDiffPlan {
        let existingSet = Set(existingIDs)
        let nextIDs = nextRects.map(\.id)
        let nextSet = Set(nextIDs)

        return TreemapLayerDiffPlan(
            retainedIDs: nextIDs.filter { existingSet.contains($0) },
            insertedIDs: nextIDs.filter { !existingSet.contains($0) },
            removedIDs: existingIDs.filter { !nextSet.contains($0) }
        )
    }
}

struct TreemapLayerSurface: NSViewRepresentable {
    let rects: [TreemapRect]
    let revision: Int
    let animateStructuralChanges: Bool
    let highlightedNodeID: UUID?
    let hoveredNodeID: UUID?
    let reduceMotion: Bool
    let pulseTargetID: UUID?
    let shouldRenderPulse: Bool
    let zoomScale: CGFloat
    let zoomAnchor: UnitPoint
    let onHover: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TreemapLayerHostingView {
        let view = TreemapLayerHostingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: TreemapLayerHostingView, context: Context) {
        nsView.onHover = onHover
        nsView.update(
            with: TreemapLayerSnapshot(
                rects: rects,
                revision: revision,
                animateStructuralChanges: animateStructuralChanges,
                highlightedNodeID: highlightedNodeID,
                hoveredNodeID: hoveredNodeID,
                reduceMotion: reduceMotion,
                pulseTargetID: pulseTargetID,
                shouldRenderPulse: shouldRenderPulse,
                zoomScale: zoomScale,
                zoomAnchor: zoomAnchor
            )
        )
    }
}

private struct TreemapLayerSnapshot {
    let rects: [TreemapRect]
    let revision: Int
    let animateStructuralChanges: Bool
    let highlightedNodeID: UUID?
    let hoveredNodeID: UUID?
    let reduceMotion: Bool
    let pulseTargetID: UUID?
    let shouldRenderPulse: Bool
    let zoomScale: CGFloat
    let zoomAnchor: UnitPoint
}

final class TreemapLayerHostingView: NSView {
    var onHover: ((CGPoint?) -> Void)?

    override var isFlipped: Bool { true }

    private let zoomLayer = CALayer()
    private let rectContainerLayer = CALayer()
    private let labelContainerLayer = CALayer()
    private let overlayContainerLayer = CALayer()
    // The live treemap needs sibling dimming plus parent and active borders,
    // so keep a tiny fixed overlay group instead of forcing everything into one shape layer.
    private let dimmingLayer = CAShapeLayer()
    private let parentBorderLayer = CAShapeLayer()
    private let highlightBorderLayer = CAShapeLayer()

    private var trackingArea: NSTrackingArea?
    private var shapeLayersByID: [UUID: CAShapeLayer] = [:]
    private var currentRectsByID: [UUID: TreemapRect] = [:]
    private var currentTopLevelRects: [TreemapRect] = []
    private var currentOrderedIDs: [UUID] = []
    private var currentRevision = -1
    private var currentContentsScale: CGFloat = 2
    private var currentPulseTargetID: UUID?
    private var pulseEnabled = false
    private var currentZoomScale: CGFloat = 1
    private var currentZoomAnchor: UnitPoint = .center

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.isGeometryFlipped = true
        layer = rootLayer
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        zoomLayer.isGeometryFlipped = true
        rectContainerLayer.isGeometryFlipped = true
        labelContainerLayer.isGeometryFlipped = true
        overlayContainerLayer.isGeometryFlipped = true

        layer?.addSublayer(zoomLayer)
        zoomLayer.addSublayer(rectContainerLayer)
        zoomLayer.addSublayer(labelContainerLayer)
        zoomLayer.addSublayer(overlayContainerLayer)

        overlayContainerLayer.addSublayer(dimmingLayer)
        overlayContainerLayer.addSublayer(parentBorderLayer)
        overlayContainerLayer.addSublayer(highlightBorderLayer)

        dimmingLayer.fillColor = NSColor.black.withAlphaComponent(0.5).cgColor
        dimmingLayer.strokeColor = nil

        parentBorderLayer.fillColor = nil
        parentBorderLayer.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        parentBorderLayer.lineWidth = 2

        highlightBorderLayer.fillColor = nil
        highlightBorderLayer.lineWidth = 2

        updateContentsScale()
        updateContainerFrames()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateContainerFrames()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )

        trackingArea = newTrackingArea
        addTrackingArea(newTrackingArea)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onHover?(location)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

    fileprivate func update(with snapshot: TreemapLayerSnapshot) {
        updateContainerFrames()
        if snapshot.zoomScale != currentZoomScale || snapshot.zoomAnchor != currentZoomAnchor {
            applyZoom(scale: snapshot.zoomScale, anchor: snapshot.zoomAnchor)
            currentZoomScale = snapshot.zoomScale
            currentZoomAnchor = snapshot.zoomAnchor
        }

        let revisionChanged = snapshot.revision != currentRevision
        if revisionChanged {
            applyStructuralSnapshot(snapshot)
            currentRevision = snapshot.revision
        }

        applyOverlay(
            highlightedNodeID: snapshot.highlightedNodeID,
            hoveredNodeID: snapshot.hoveredNodeID
        )

        if revisionChanged ||
            snapshot.pulseTargetID != currentPulseTargetID ||
            snapshot.shouldRenderPulse != pulseEnabled {
            updatePulse(
                targetID: snapshot.pulseTargetID,
                isEnabled: snapshot.shouldRenderPulse,
                reduceMotion: snapshot.reduceMotion
            )
            currentPulseTargetID = snapshot.pulseTargetID
            pulseEnabled = snapshot.shouldRenderPulse
        }
    }

    private func updateContainerFrames() {
        guard let rootLayer = layer else { return }

        rootLayer.frame = bounds
        zoomLayer.frame = bounds
        rectContainerLayer.frame = zoomLayer.bounds
        labelContainerLayer.frame = zoomLayer.bounds
        overlayContainerLayer.frame = zoomLayer.bounds

        dimmingLayer.frame = overlayContainerLayer.bounds
        parentBorderLayer.frame = overlayContainerLayer.bounds
        highlightBorderLayer.frame = overlayContainerLayer.bounds
    }

    private func applyStructuralSnapshot(_ snapshot: TreemapLayerSnapshot) {
        let renderableRects = snapshot.rects.filter(\.isRenderableDisplayRect)
        let diff = TreemapLayerDiffPlan.make(
            existingIDs: currentOrderedIDs,
            nextRects: renderableRects
        )
        let nextRectsByID = Dictionary(uniqueKeysWithValues: snapshot.rects.map { ($0.id, $0) })
        let nextTopLevelRects = snapshot.rects.filter { $0.depth == 0 }
        let shouldAnimate = snapshot.animateStructuralChanges &&
            !snapshot.reduceMotion &&
            !currentOrderedIDs.isEmpty

        CATransaction.begin()
        if shouldAnimate {
            CATransaction.setAnimationDuration(0.24)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }

        var removedLayers: [CAShapeLayer] = []

        for removedID in diff.removedIDs {
            guard let layer = shapeLayersByID[removedID] else { continue }
            let currentRect = currentRectsByID[removedID]

            if shouldAnimate, let currentRect {
                apply(rect: currentRect.collapsedDisplayRect, to: layer, color: currentRect.color, depth: currentRect.depth, opacity: 0)
                removedLayers.append(layer)
            } else {
                layer.removeFromSuperlayer()
                shapeLayersByID[removedID] = nil
            }
        }

        for (index, rect) in renderableRects.enumerated() {
            let layer = shapeLayersByID[rect.id] ?? makeShapeLayer(for: rect)

            if shapeLayersByID[rect.id] == nil {
                shapeLayersByID[rect.id] = layer
                rectContainerLayer.addSublayer(layer)

                if shouldAnimate {
                    apply(rect: rect.collapsedDisplayRect, to: layer, color: rect.color, depth: rect.depth, opacity: 0)
                }
            }

            rectContainerLayer.insertSublayer(layer, at: UInt32(index))
            apply(rect: rect.displayRect, to: layer, color: rect.color, depth: rect.depth, opacity: 1)
        }

        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }

            for layer in removedLayers {
                layer.removeFromSuperlayer()
            }

            for removedID in diff.removedIDs {
                self.shapeLayersByID[removedID] = nil
            }
        }
        CATransaction.commit()

        currentRectsByID = nextRectsByID
        currentTopLevelRects = nextTopLevelRects
        currentOrderedIDs = renderableRects.map(\.id)

        rebuildLabelLayers(using: snapshot.rects)
    }

    private func makeShapeLayer(for rect: TreemapRect) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.contentsScale = currentContentsScale
        layer.actions = [
            "contents": NSNull(),
            "hidden": NSNull()
        ]
        apply(rect: rect.displayRect, to: layer, color: rect.color, depth: rect.depth, opacity: 1)
        return layer
    }

    private func apply(
        rect: CGRect,
        to layer: CAShapeLayer,
        color: Color,
        depth: Int,
        opacity: Float
    ) {
        let safeRect = rect.standardized
        let cornerRadius = depth == 0 ? CGFloat(2) : CGFloat(1)
        let pathRect = CGRect(origin: .zero, size: safeRect.size)

        layer.frame = safeRect
        layer.path = CGPath(
            roundedRect: pathRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        layer.fillColor = NSColor(color).cgColor
        layer.strokeColor = depth < 2 ? NSColor.black.withAlphaComponent(0.2).cgColor : nil
        layer.lineWidth = depth < 2 ? 0.5 : 0
        layer.opacity = opacity
    }

    private func rebuildLabelLayers(using rects: [TreemapRect]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        labelContainerLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        for rect in rects where rect.shouldShowTopLevelLabel {
            guard let labelLayers = makeLabelLayers(for: rect) else { continue }
            labelContainerLayer.addSublayer(labelLayers.nameLayer)

            if let sizeLayer = labelLayers.sizeLayer {
                labelContainerLayer.addSublayer(sizeLayer)
            }
        }

        CATransaction.commit()
    }

    private func makeLabelLayers(for rect: TreemapRect) -> TreemapTextLayers? {
        let labelLayout = rect.labelLayout
        guard let displayName = labelLayout.displayName else { return nil }

        let nameLayer = CATextLayer()
        nameLayer.contentsScale = currentContentsScale
        nameLayer.frame = labelLayout.nameFrame
        nameLayer.alignmentMode = .left
        nameLayer.truncationMode = .end
        nameLayer.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        nameLayer.shadowOpacity = 1
        nameLayer.shadowRadius = 1.5
        nameLayer.shadowOffset = CGSize(width: 0, height: 1)
        nameLayer.string = NSAttributedString(
            string: displayName,
            attributes: [
                .font: NSFont.systemFont(ofSize: labelLayout.fontSize, weight: .medium),
                .foregroundColor: NSColor.white
            ]
        )

        let sizeLayer: CATextLayer?
        if let sizeFrame = labelLayout.sizeFrame {
            let layer = CATextLayer()
            layer.contentsScale = currentContentsScale
            layer.frame = sizeFrame
            layer.alignmentMode = .left
            layer.truncationMode = .end
            layer.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 1.5
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.string = NSAttributedString(
                string: rect.node.formattedSize,
                attributes: [
                    .font: NSFont.systemFont(ofSize: labelLayout.fontSize - 1),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.8)
                ]
            )
            sizeLayer = layer
        } else {
            sizeLayer = nil
        }

        return TreemapTextLayers(nameLayer: nameLayer, sizeLayer: sizeLayer)
    }

    private func applyOverlay(
        highlightedNodeID: UUID?,
        hoveredNodeID: UUID?
    ) {
        let plan = TreemapOverlayPlan.make(
            rectsByID: currentRectsByID,
            topLevelRects: currentTopLevelRects,
            highlightedNodeID: highlightedNodeID,
            hoveredNodeID: hoveredNodeID
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if plan.dimmedTopLevelRectIDs.isEmpty {
            dimmingLayer.path = nil
        } else {
            let path = CGMutablePath()

            for dimmedID in plan.dimmedTopLevelRectIDs {
                guard let rect = currentRectsByID[dimmedID] else { continue }
                path.addPath(rect.overlayTopLevelPath)
            }

            dimmingLayer.path = path
        }

        if let parentID = plan.parentRectID, let rect = currentRectsByID[parentID] {
            parentBorderLayer.path = rect.overlayTopLevelPath
            parentBorderLayer.isHidden = false
        } else {
            parentBorderLayer.path = nil
            parentBorderLayer.isHidden = true
        }

        if let highlightID = plan.highlightRectID,
           let rect = currentRectsByID[highlightID] {
            highlightBorderLayer.path = rect.highlightPath
            highlightBorderLayer.strokeColor = switch plan.highlightStyle {
            case .hover:
                NSColor.systemYellow.cgColor
            case .treeSelection:
                NSColor.systemCyan.cgColor
            case .none:
                nil
            }
            highlightBorderLayer.isHidden = false
        } else {
            highlightBorderLayer.path = nil
            highlightBorderLayer.isHidden = true
        }

        CATransaction.commit()
    }

    private func updatePulse(
        targetID: UUID?,
        isEnabled: Bool,
        reduceMotion: Bool
    ) {
        guard !reduceMotion else {
            resetPulseLayers(except: nil)
            return
        }

        guard isEnabled, let targetID else {
            resetPulseLayers(except: nil)
            return
        }

        for (id, layer) in shapeLayersByID {
            guard id == targetID else {
                layer.removeAnimation(forKey: "treemapPulse")
                layer.transform = CATransform3DIdentity
                continue
            }

            if layer.animation(forKey: "treemapPulse") == nil {
                layer.transform = CATransform3DIdentity

                let animation = CABasicAnimation(keyPath: "transform.scale")
                animation.fromValue = 1
                animation.toValue = 1.02
                animation.duration = 2
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: "treemapPulse")
            }
        }
    }

    private func resetPulseLayers(except targetID: UUID?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (id, layer) in shapeLayersByID where id != targetID {
            layer.removeAnimation(forKey: "treemapPulse")
            layer.transform = CATransform3DIdentity
        }

        if let targetID {
            shapeLayersByID[targetID]?.transform = CATransform3DIdentity
        }

        CATransaction.commit()
    }

    private func applyZoom(scale: CGFloat, anchor: UnitPoint) {
        let anchorPoint = VisualizationZoomState.anchorPoint(for: anchor, in: bounds.size)
        let transform = CGAffineTransform(translationX: anchorPoint.x, y: anchorPoint.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -anchorPoint.x, y: -anchorPoint.y)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        zoomLayer.setAffineTransform(transform)
        CATransaction.commit()
    }

    private func updateContentsScale() {
        currentContentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for layer in shapeLayersByID.values {
            layer.contentsScale = currentContentsScale
        }

        for layer in labelContainerLayer.sublayers ?? [] {
            layer.contentsScale = currentContentsScale
        }

        dimmingLayer.contentsScale = currentContentsScale
        parentBorderLayer.contentsScale = currentContentsScale
        highlightBorderLayer.contentsScale = currentContentsScale

        CATransaction.commit()
    }
}

private struct TreemapTextLayers {
    let nameLayer: CATextLayer
    let sizeLayer: CATextLayer?
}

private struct TreemapLabelLayout {
    let displayName: String?
    let nameFrame: CGRect
    let sizeFrame: CGRect?
    let fontSize: CGFloat
}

private extension TreemapRect {
    var displayPadding: CGFloat {
        depth == 0 ? 1.0 : 0.5
    }

    var displayRect: CGRect {
        cgRect.insetBy(dx: displayPadding, dy: displayPadding)
    }

    var isRenderableDisplayRect: Bool {
        displayRect.width > 0.5 && displayRect.height > 0.5
    }

    var collapsedDisplayRect: CGRect {
        CGRect(x: center.x, y: center.y, width: 0, height: 0)
    }

    var overlayTopLevelPath: CGPath {
        let rect = cgRect.insetBy(dx: 1, dy: 1)
        return CGPath(
            roundedRect: rect,
            cornerWidth: 2,
            cornerHeight: 2,
            transform: nil
        )
    }

    var highlightPath: CGPath {
        CGPath(
            roundedRect: displayRect,
            cornerWidth: depth == 0 ? 2 : 1,
            cornerHeight: depth == 0 ? 2 : 1,
            transform: nil
        )
    }

    var shouldShowTopLevelLabel: Bool {
        depth == 0 && displayRect.width > 50 && displayRect.height > 25
    }

    var labelLayout: TreemapLabelLayout {
        let padding: CGFloat = 4
        let rect = displayRect
        let width = rect.width - padding * 2
        let height = rect.height - padding * 2

        guard width > 25, height > 12 else {
            return TreemapLabelLayout(
                displayName: nil,
                nameFrame: .zero,
                sizeFrame: nil,
                fontSize: 0
            )
        }

        let fontSize = min(max(9, height / 4), 12)
        let maxChars = Int(width / (fontSize * 0.55))
        guard maxChars >= 3 else {
            return TreemapLabelLayout(
                displayName: nil,
                nameFrame: .zero,
                sizeFrame: nil,
                fontSize: fontSize
            )
        }

        var displayName = node.name
        if displayName.count > maxChars {
            displayName = String(displayName.prefix(maxChars - 1)) + "…"
        }

        let nameFrame = CGRect(
            x: rect.minX + padding,
            y: rect.minY + padding,
            width: width,
            height: fontSize + 4
        )

        let sizeFrame: CGRect?
        if height > 30 {
            sizeFrame = CGRect(
                x: rect.minX + padding,
                y: rect.minY + padding + fontSize + 8,
                width: width,
                height: fontSize + 3
            )
        } else {
            sizeFrame = nil
        }

        return TreemapLabelLayout(
            displayName: displayName,
            nameFrame: nameFrame,
            sizeFrame: sizeFrame,
            fontSize: fontSize
        )
    }
}
