import XCTest
@testable import DataX

final class TreemapLayerRendererTests: XCTestCase {
    func testTreemapBlockLayerSupportsCoreAnimationCopies() {
        let layer = TreemapBlockLayer()
        layer.apply(
            rect: CGRect(x: 10, y: 20, width: 80, height: 60),
            style: TreemapShadingStyle(
                fillColor: .blue,
                gradientStartColor: .white,
                gradientEndColor: .blue
            ),
            depth: 0,
            opacity: 0.75
        )
        layer.updateContentsScale(2)

        let copy = TreemapBlockLayer(layer: layer)

        XCTAssertEqual(copy.frame, layer.frame)
        XCTAssertEqual(copy.opacity, layer.opacity)
        XCTAssertEqual(copy.contentsScale, 2)
        XCTAssertEqual(copy.sublayers?.count, 2)
    }

    func testOverlayPlanPrefersHoveredNodeAndDimsSiblingTopLevelRects() {
        let rootA = makeRect(path: "/root/A", depth: 0, x: 0, y: 0, width: 120, height: 120)
        let rootB = makeRect(path: "/root/B", depth: 0, x: 120, y: 0, width: 120, height: 120)
        let child = makeRect(path: "/root/A/child", depth: 1, x: 12, y: 12, width: 48, height: 48)

        let plan = TreemapOverlayPlan.make(
            rects: [rootA, rootB, child],
            highlightedNodeID: rootB.id,
            hoveredNodeID: child.id
        )

        XCTAssertEqual(plan.highlightRectID, child.id)
        XCTAssertEqual(plan.parentRectID, rootA.id)
        XCTAssertEqual(plan.highlightStyle, .hover)
        XCTAssertEqual(plan.dimmedTopLevelRectIDs, [rootB.id])
    }

    func testOverlayPlanFallsBackToTreeHighlightWhenHoverIsAbsent() {
        let rootA = makeRect(path: "/root/A", depth: 0, x: 0, y: 0, width: 120, height: 120)
        let rootB = makeRect(path: "/root/B", depth: 0, x: 120, y: 0, width: 120, height: 120)

        let plan = TreemapOverlayPlan.make(
            rects: [rootA, rootB],
            highlightedNodeID: rootB.id,
            hoveredNodeID: nil
        )

        XCTAssertEqual(plan.highlightRectID, rootB.id)
        XCTAssertEqual(plan.parentRectID, rootB.id)
        XCTAssertEqual(plan.highlightStyle, .treeSelection)
        XCTAssertEqual(plan.dimmedTopLevelRectIDs, [rootA.id])
    }

    func testLayerDiffPlanSeparatesInsertedRetainedAndRemovedIDs() {
        let retained = UUID()
        let removed = UUID()
        let inserted = UUID()

        let plan = TreemapLayerDiffPlan.make(
            existingIDs: [retained, removed],
            nextRects: [
                makeRect(path: "/root/retained", depth: 0, x: 0, y: 0, width: 80, height: 80, id: retained),
                makeRect(path: "/root/inserted", depth: 0, x: 80, y: 0, width: 80, height: 80, id: inserted)
            ]
        )

        XCTAssertEqual(plan.retainedIDs, [retained])
        XCTAssertEqual(plan.insertedIDs, [inserted])
        XCTAssertEqual(plan.removedIDs, [removed])
    }

    private func makeRect(
        path: String,
        depth: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        id: UUID? = nil
    ) -> TreemapRect {
        let node = FileNode(
            id: id ?? UUID(),
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: URL(fileURLWithPath: path),
            isDirectory: true,
            isHidden: false,
            isSymlink: false,
            fileExtension: nil,
            modificationDate: nil,
            size: UInt64(max(width * height, 1)),
            fileCount: 0,
            children: []
        )

        return TreemapRect(
            id: node.id,
            x: x,
            y: y,
            width: width,
            height: height,
            node: node,
            depth: depth,
            color: .blue
        )
    }
}
