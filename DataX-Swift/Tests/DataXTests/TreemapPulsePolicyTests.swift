import XCTest
@testable import DataX

final class TreemapPulsePolicyTests: XCTestCase {
    func testLargestVisibleTopLevelRectIgnoresNestedRects() {
        let largest = makeFile("/root/largest.mov", size: 600)
        let second = makeFile("/root/second.zip", size: 300)
        let nestedParent = makeDirectory("/root/folder")
        let nestedChild = makeFile("/root/folder/deep.dat", size: 900)

        let rects = [
            makeRect(node: largest, depth: 0, x: 0, y: 0, width: 40, height: 20),
            makeRect(node: second, depth: 0, x: 40, y: 0, width: 20, height: 20),
            makeRect(node: nestedParent, depth: 0, x: 0, y: 20, width: 10, height: 10),
            makeRect(node: nestedChild, depth: 1, x: 1, y: 21, width: 80, height: 80)
        ]

        let target = TreemapPulsePolicy.largestVisibleTopLevelRect(in: rects)

        XCTAssertEqual(target?.node.id, largest.id)
        XCTAssertEqual(target?.depth, 0)
        XCTAssertNotEqual(target?.node.id, nestedChild.id)
    }

    func testLargestVisibleTopLevelRectReturnsNilWhenNoTopLevelRectsExist() {
        let nested = makeFile("/root/nested.tmp", size: 42)
        let rects = [
            makeRect(node: nested, depth: 1, x: 0, y: 0, width: 10, height: 10)
        ]

        XCTAssertNil(TreemapPulsePolicy.largestVisibleTopLevelRect(in: rects))
    }

    func testRenderPulseRequiresIdleStateWithoutReduceMotion() {
        XCTAssertTrue(
            TreemapPulsePolicy.shouldRenderPulse(
                reduceMotion: false,
                hasHover: false,
                hasHighlight: false
            )
        )
        XCTAssertFalse(
            TreemapPulsePolicy.shouldRenderPulse(
                reduceMotion: true,
                hasHover: false,
                hasHighlight: false
            )
        )
        XCTAssertFalse(
            TreemapPulsePolicy.shouldRenderPulse(
                reduceMotion: false,
                hasHover: true,
                hasHighlight: false
            )
        )
        XCTAssertFalse(
            TreemapPulsePolicy.shouldRenderPulse(
                reduceMotion: false,
                hasHover: false,
                hasHighlight: true
            )
        )
    }

    private func makeDirectory(_ path: String) -> FileNode {
        FileNode(url: URL(fileURLWithPath: path), isDirectory: true)
    }

    private func makeFile(_ path: String, size: UInt64) -> FileNode {
        FileNode(url: URL(fileURLWithPath: path), isDirectory: false, size: size)
    }

    private func makeRect(
        node: FileNode,
        depth: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> TreemapRect {
        TreemapRect(
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
