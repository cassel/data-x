import CoreGraphics
import Dispatch
import XCTest
@testable import DataX

final class TreemapSpatialIndexTests: XCTestCase {
    func testResolveHitPrefersDeepestNestedRect() {
        let rootBounds = CGRect(x: 0, y: 0, width: 120, height: 120)
        let parent = makeRect(path: "/root/parent", depth: 0, x: 0, y: 0, width: 120, height: 120)
        let child = makeRect(path: "/root/parent/child", depth: 1, x: 10, y: 10, width: 70, height: 70)
        let grandchild = makeRect(path: "/root/parent/child/grandchild", depth: 2, x: 15, y: 15, width: 20, height: 20)

        var index = TreemapSpatialIndex(bounds: rootBounds, minCellSize: 8, bucketSize: 4)
        index.insert(TreemapHitTestEntry(rect: parent))
        index.insert(TreemapHitTestEntry(rect: child))
        index.insert(TreemapHitTestEntry(rect: grandchild))

        let result = TreemapHoverResolver.resolve(
            point: CGPoint(x: 20, y: 20),
            candidates: index.candidates(at: CGPoint(x: 20, y: 20))
        )

        XCTAssertEqual(result?.id, grandchild.id)
        XCTAssertEqual(result?.depth, grandchild.depth)
    }

    func testResolveHitReturnsNilForMiss() {
        let rect = makeRect(path: "/root/file.bin", depth: 0, x: 10, y: 10, width: 20, height: 20)
        var index = TreemapSpatialIndex(bounds: CGRect(x: 0, y: 0, width: 100, height: 100), minCellSize: 8, bucketSize: 4)
        index.insert(TreemapHitTestEntry(rect: rect))

        let result = TreemapHoverResolver.resolve(
            point: CGPoint(x: 80, y: 80),
            candidates: index.candidates(at: CGPoint(x: 80, y: 80))
        )

        XCTAssertNil(result)
    }

    func testResolveHitUsesSmallerAreaAsTieBreakerAtSameDepth() {
        let large = makeRect(path: "/root/large", depth: 1, x: 10, y: 10, width: 60, height: 60)
        let small = makeRect(path: "/root/small", depth: 1, x: 20, y: 20, width: 20, height: 20)

        var index = TreemapSpatialIndex(bounds: CGRect(x: 0, y: 0, width: 100, height: 100), minCellSize: 8, bucketSize: 4)
        index.insert(TreemapHitTestEntry(rect: large))
        index.insert(TreemapHitTestEntry(rect: small))

        let result = TreemapHoverResolver.resolve(
            point: CGPoint(x: 25, y: 25),
            candidates: index.candidates(at: CGPoint(x: 25, y: 25))
        )

        XCTAssertEqual(result?.id, small.id)
    }

    func testRebuildingIndexReflectsUpdatedRects() {
        let original = makeRect(path: "/root/movable", depth: 0, x: 10, y: 10, width: 20, height: 20)
        let moved = makeRect(path: "/root/movable", depth: 0, x: 60, y: 60, width: 20, height: 20, id: original.id)

        var initialIndex = TreemapSpatialIndex(bounds: CGRect(x: 0, y: 0, width: 100, height: 100), minCellSize: 8, bucketSize: 4)
        initialIndex.insert(TreemapHitTestEntry(rect: original))

        XCTAssertEqual(
            TreemapHoverResolver.resolve(
                point: CGPoint(x: 15, y: 15),
                candidates: initialIndex.candidates(at: CGPoint(x: 15, y: 15))
            )?.id,
            original.id
        )
        XCTAssertNil(
            TreemapHoverResolver.resolve(
                point: CGPoint(x: 65, y: 65),
                candidates: initialIndex.candidates(at: CGPoint(x: 65, y: 65))
            )
        )

        var rebuiltIndex = TreemapSpatialIndex(bounds: CGRect(x: 0, y: 0, width: 100, height: 100), minCellSize: 8, bucketSize: 4)
        rebuiltIndex.insert(TreemapHitTestEntry(rect: moved))

        XCTAssertNil(
            TreemapHoverResolver.resolve(
                point: CGPoint(x: 15, y: 15),
                candidates: rebuiltIndex.candidates(at: CGPoint(x: 15, y: 15))
            )
        )
        XCTAssertEqual(
            TreemapHoverResolver.resolve(
                point: CGPoint(x: 65, y: 65),
                candidates: rebuiltIndex.candidates(at: CGPoint(x: 65, y: 65))
            )?.id,
            moved.id
        )
    }

    func testPointQueriesBenchmarkAtEightThousandRects() {
        var index = TreemapSpatialIndex(bounds: CGRect(x: 0, y: 0, width: 400, height: 400), minCellSize: 4, bucketSize: 8)
        let rects = makeGridRects(count: 8_000, columns: 100, cellSize: 4)

        for rect in rects {
            index.insert(TreemapHitTestEntry(rect: rect))
        }

        let samplePoints = stride(from: 0, to: 4_000, by: 5).map { offset in
            CGPoint(x: CGFloat((offset * 7) % 400), y: CGFloat((offset * 11) % 400))
        }

        var perQueryMilliseconds: [Double] = []
        perQueryMilliseconds.reserveCapacity(8)

        for iteration in 0..<10 {
            let start = DispatchTime.now().uptimeNanoseconds

            for point in samplePoints {
                _ = TreemapHoverResolver.resolve(point: point, candidates: index.candidates(at: point))
            }

            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start
            let averagePerQueryMilliseconds = Double(elapsedNanoseconds) / Double(samplePoints.count) / 1_000_000

            if iteration >= 2 {
                perQueryMilliseconds.append(averagePerQueryMilliseconds)
            }
        }

        let sortedSamples = perQueryMilliseconds.sorted()
        let medianMilliseconds = sortedSamples[sortedSamples.count / 2]

        XCTAssertLessThan(
            medianMilliseconds,
            1.0,
            "Expected point-query median under 1ms, got \(medianMilliseconds)ms"
        )
    }

    private func makeGridRects(count: Int, columns: Int, cellSize: CGFloat) -> [TreemapRect] {
        (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            return makeRect(
                path: "/root/item-\(index)",
                depth: 0,
                x: Double(CGFloat(column) * cellSize),
                y: Double(CGFloat(row) * cellSize),
                width: Double(cellSize),
                height: Double(cellSize)
            )
        }
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
