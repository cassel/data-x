import CoreGraphics
import XCTest
@testable import DataX

final class VisualizationAccessibilityTests: XCTestCase {
    func testPercentFormatterUsesStableSingleDecimalPrecision() {
        XCTAssertEqual(
            VisualizationAccessibilityFormatter.percentText(part: 1, of: 8),
            "12.5%"
        )
        XCTAssertEqual(
            VisualizationAccessibilityFormatter.percentText(part: 1, of: 3),
            "33.3%"
        )
        XCTAssertEqual(
            VisualizationAccessibilityFormatter.percentText(part: 1, of: 4),
            "25%"
        )
    }

    func testTreemapAccessibilityValueIncludesSizeAndPercentOfParent() {
        XCTAssertEqual(
            VisualizationAccessibilityFormatter.treemapValue(
                sizeText: "2 GB",
                part: 2,
                parent: 8
            ),
            "2 GB, 25% of parent"
        )
    }

    func testSunburstAccessibilityValueIncludesPercentAndDepthLevel() {
        XCTAssertEqual(
            VisualizationAccessibilityFormatter.sunburstValue(
                sizeText: "2 GB",
                depth: 2,
                part: 2,
                parent: 8
            ),
            "2 GB, 25% of parent, depth level 3"
        )
    }

    func testTreemapNavigationPrefersOrthogonalOverlapBeforeShorterDistance() {
        let current = TreemapAccessibilityNode(
            id: UUID(),
            frame: CGRect(x: 60, y: 40, width: 20, height: 20),
            depth: 2
        )
        let overlappingCandidate = TreemapAccessibilityNode(
            id: UUID(),
            frame: CGRect(x: 25, y: 42, width: 25, height: 18),
            depth: 2
        )
        let diagonalCandidate = TreemapAccessibilityNode(
            id: UUID(),
            frame: CGRect(x: 35, y: 5, width: 20, height: 20),
            depth: 2
        )

        let nextID = TreemapAccessibilityNavigation.nextID(
            from: current.id,
            in: [current, overlappingCandidate, diagonalCandidate],
            direction: .left
        )

        XCTAssertEqual(nextID, overlappingCandidate.id)
    }

    func testTreemapNavigationUsesSameDepthTieBreakerAfterDistance() {
        let current = TreemapAccessibilityNode(
            id: UUID(),
            frame: CGRect(x: 20, y: 20, width: 20, height: 20),
            depth: 2
        )
        let sameDepth = TreemapAccessibilityNode(
            id: UUID(),
            frame: CGRect(x: 50, y: 22, width: 20, height: 16),
            depth: 2
        )
        let differentDepth = TreemapAccessibilityNode(
            id: UUID(),
            frame: CGRect(x: 50, y: 22, width: 20, height: 16),
            depth: 1
        )

        let nextID = TreemapAccessibilityNavigation.nextID(
            from: current.id,
            in: [current, sameDepth, differentDepth],
            direction: .right
        )

        XCTAssertEqual(nextID, sameDepth.id)
    }

    func testSunburstNavigationMovesWithinRingAndHierarchy() {
        let left = SunburstAccessibilityNode(
            id: UUID(),
            depth: 1,
            startAngle: 0.0,
            endAngle: 0.4,
            parentID: UUID()
        )
        let parent = SunburstAccessibilityNode(
            id: left.parentID!,
            depth: 0,
            startAngle: 0.0,
            endAngle: 1.2,
            parentID: nil
        )
        let current = SunburstAccessibilityNode(
            id: UUID(),
            depth: 1,
            startAngle: 0.4,
            endAngle: 0.8,
            parentID: parent.id
        )
        let right = SunburstAccessibilityNode(
            id: UUID(),
            depth: 1,
            startAngle: 0.8,
            endAngle: 1.1,
            parentID: parent.id
        )
        let firstChild = SunburstAccessibilityNode(
            id: UUID(),
            depth: 2,
            startAngle: 0.42,
            endAngle: 0.55,
            parentID: current.id
        )

        let nodes = [left, parent, current, right, firstChild]

        XCTAssertEqual(
            SunburstAccessibilityNavigation.nextID(from: current.id, in: nodes, direction: .left),
            left.id
        )
        XCTAssertEqual(
            SunburstAccessibilityNavigation.nextID(from: current.id, in: nodes, direction: .right),
            right.id
        )
        XCTAssertEqual(
            SunburstAccessibilityNavigation.nextID(from: current.id, in: nodes, direction: .up),
            parent.id
        )
        XCTAssertEqual(
            SunburstAccessibilityNavigation.nextID(from: current.id, in: nodes, direction: .down),
            firstChild.id
        )
    }

    func testSunburstNavigationFallsBackToVisibleInnerAndOuterRings() {
        let visibleInner = SunburstAccessibilityNode(
            id: UUID(),
            depth: 1,
            startAngle: 0.0,
            endAngle: 1.1,
            parentID: UUID()
        )
        let current = SunburstAccessibilityNode(
            id: UUID(),
            depth: 2,
            startAngle: 0.3,
            endAngle: 0.6,
            parentID: UUID()
        )
        let visibleOuter = SunburstAccessibilityNode(
            id: UUID(),
            depth: 3,
            startAngle: 0.4,
            endAngle: 0.5,
            parentID: UUID()
        )

        let nodes = [visibleInner, current, visibleOuter]

        XCTAssertEqual(
            SunburstAccessibilityNavigation.nextID(from: current.id, in: nodes, direction: .up),
            visibleInner.id
        )
        XCTAssertEqual(
            SunburstAccessibilityNavigation.nextID(from: current.id, in: nodes, direction: .down),
            visibleOuter.id
        )
    }
}
