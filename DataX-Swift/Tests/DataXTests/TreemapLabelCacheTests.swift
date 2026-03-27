import XCTest
@testable import DataX

final class TreemapLabelCacheTests: XCTestCase {

    // MARK: - AC 9.1.1: Stored let property computed once at init

    func testLabelLayoutIsStoredLetComputedAtInit() {
        let rect = makeRect(name: "Documents", size: 1024, depth: 0,
                            x: 0, y: 0, width: 200, height: 80)

        // Stored property returns a layout for a large depth-0 rect
        XCTAssertNotNil(rect.labelLayout)
        XCTAssertEqual(rect.labelLayout?.displayName, "Documents")
    }

    func testLabelLayoutIsNilForDeepRects() {
        let rect = makeRect(name: "file.txt", size: 512, depth: 1,
                            x: 10, y: 10, width: 200, height: 80)

        // depth > 0 → guard returns nil in makeLayout
        XCTAssertNil(rect.labelLayout)
    }

    func testLabelLayoutIsNilForTinyRects() {
        let rect = makeRect(name: "X", size: 100, depth: 0,
                            x: 0, y: 0, width: 20, height: 10)

        // Too small to fit a label
        XCTAssertNil(rect.labelLayout)
    }

    // MARK: - AC 9.1.2: Labels display correctly

    func testLabelLayoutTruncatesLongNames() {
        let rect = makeRect(
            name: "VeryLongDirectoryNameThatNeedsTruncation",
            size: 4096, depth: 0,
            x: 0, y: 0, width: 104, height: 40
        )

        XCTAssertNotNil(rect.labelLayout)
        XCTAssertTrue(rect.labelLayout!.displayName.hasSuffix("…"))
    }

    func testShouldShowTopLevelLabelReadsStoredProperty() {
        let large = makeRect(name: "Photos", size: 2048, depth: 0,
                             x: 0, y: 0, width: 200, height: 80)
        let deep = makeRect(name: "child", size: 100, depth: 2,
                            x: 0, y: 0, width: 200, height: 80)

        XCTAssertTrue(large.shouldShowTopLevelLabel)
        XCTAssertFalse(deep.shouldShowTopLevelLabel)
    }

    // MARK: - AC 9.1.3: Zero per-frame overhead

    func testLabelLayoutIsIdenticalAcrossMultipleAccesses() {
        let rect = makeRect(name: "Downloads", size: 8192, depth: 0,
                            x: 0, y: 0, width: 200, height: 80)

        // Multiple accesses return the same stored value (O(1), no recomputation)
        let first = rect.labelLayout
        let second = rect.labelLayout
        XCTAssertEqual(first, second)
    }

    func testInsetRectSkipsLabelComputation() {
        let rect = makeRect(name: "Root", size: 4096, depth: 0,
                            x: 0, y: 0, width: 200, height: 80)

        let insetRect = rect.inset(by: 1.5)

        // inset(by:) passes .some(nil) — labelLayout is nil regardless of size
        XCTAssertNil(insetRect.labelLayout)
    }

    // MARK: - Helpers

    private func makeRect(
        name: String,
        size: UInt64,
        depth: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> TreemapRect {
        let node = FileNode(
            id: UUID(),
            name: name,
            path: URL(fileURLWithPath: "/test/\(name)"),
            isDirectory: true,
            isHidden: false,
            isSymlink: false,
            fileExtension: nil,
            modificationDate: nil,
            size: size,
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
