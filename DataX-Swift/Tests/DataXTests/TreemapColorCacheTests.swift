import XCTest
@testable import DataX

final class TreemapColorCacheTests: XCTestCase {

    // MARK: - AC 9.2.1: Cache reuse when root and child count unchanged

    func testSameRootProducesIdenticalColors() {
        let root = makeDirectory(name: "Root", children: [
            makeFile(name: "a.swift", size: 500),
            makeFile(name: "b.png", size: 300),
            makeFile(name: "c.mp4", size: 200),
        ])
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

        let first = TreemapLayout.layout(node: root, bounds: bounds)
        let second = TreemapLayout.layout(node: root, bounds: bounds)

        // Same root, same child count → cache hit → identical colors
        XCTAssertEqual(first.count, second.count, "Rect count should be identical")
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.color, b.color, "Color for \(a.node.name) should be cached")
        }
    }

    func testSameRootDifferentBoundsReusesColors() {
        let root = makeDirectory(name: "Root", children: [
            makeFile(name: "a.swift", size: 600),
            makeFile(name: "b.png", size: 400),
        ])
        let bounds1 = CGRect(x: 0, y: 0, width: 400, height: 300)
        let bounds2 = CGRect(x: 0, y: 0, width: 800, height: 600)

        let first = TreemapLayout.layout(node: root, bounds: bounds1)
        let second = TreemapLayout.layout(node: root, bounds: bounds2)

        // Window resize: same root, same children → cache persists
        let firstColors = Dictionary(uniqueKeysWithValues: first.map { ($0.node.name, $0.color) })
        let secondColors = Dictionary(uniqueKeysWithValues: second.map { ($0.node.name, $0.color) })

        for (name, color) in firstColors {
            XCTAssertEqual(color, secondColors[name], "Color for \(name) should persist across resize")
        }
    }

    // MARK: - AC 9.2.2: Cache invalidation on navigation

    func testDifferentRootInvalidatesCache() {
        let childA = makeFile(name: "a.swift", size: 500)
        let childB = makeFile(name: "b.png", size: 300)
        let rootA = makeDirectory(name: "RootA", children: [childA, childB])

        let childC = makeFile(name: "c.mp4", size: 700)
        let childD = makeFile(name: "d.zip", size: 200)
        let rootB = makeDirectory(name: "RootB", children: [childC, childD])

        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

        // Layout with rootA first to populate cache
        let _ = TreemapLayout.layout(node: rootA, bounds: bounds)
        // Layout with rootB → different root ID → cache should invalidate
        let resultB = TreemapLayout.layout(node: rootB, bounds: bounds)

        // Verify resultB has rects for rootB's children (not rootA's)
        let names = Set(resultB.map { $0.node.name })
        XCTAssertTrue(names.contains("c.mp4"), "Should contain rootB children after navigation")
        XCTAssertTrue(names.contains("d.zip"), "Should contain rootB children after navigation")
        XCTAssertFalse(names.contains("a.swift"), "Should not contain rootA children")
    }

    // MARK: - AC 9.2.2: Cache invalidation on child count change

    func testAddingChildInvalidatesCache() {
        let child1 = makeFile(name: "a.swift", size: 500)
        let child2 = makeFile(name: "b.png", size: 300)

        // Use a fixed ID so the root identity stays the same
        let rootID = UUID()
        let root1 = makeDirectory(id: rootID, name: "Root", children: [child1, child2])
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

        let first = TreemapLayout.layout(node: root1, bounds: bounds)

        // Simulate scan adding a new child — same root ID, different child count
        let child3 = makeFile(name: "c.mp4", size: 200)
        let root2 = makeDirectory(id: rootID, name: "Root", children: [child1, child2, child3])

        let second = TreemapLayout.layout(node: root2, bounds: bounds)

        // Cache should have been invalidated — second result should include the new child
        let secondNames = Set(second.map { $0.node.name })
        XCTAssertTrue(secondNames.contains("c.mp4"), "New child should appear after cache invalidation")
        XCTAssertEqual(first.count + 1, second.count, "Should have one more rect after adding a child")
    }

    // MARK: - Helpers

    private func makeFile(name: String, size: UInt64) -> FileNode {
        let ext = name.contains(".") ? String(name.split(separator: ".").last!) : nil
        return FileNode(
            id: UUID(),
            name: name,
            path: URL(fileURLWithPath: "/test/\(name)"),
            isDirectory: false,
            isHidden: false,
            isSymlink: false,
            fileExtension: ext,
            modificationDate: nil,
            size: size,
            fileCount: 0,
            children: nil
        )
    }

    private func makeDirectory(
        id: UUID = UUID(),
        name: String,
        children: [FileNode]
    ) -> FileNode {
        let totalSize = children.reduce(0 as UInt64) { $0 + $1.size }
        return FileNode(
            id: id,
            name: name,
            path: URL(fileURLWithPath: "/test/\(name)"),
            isDirectory: true,
            isHidden: false,
            isSymlink: false,
            fileExtension: nil,
            modificationDate: nil,
            size: totalSize,
            fileCount: children.count,
            children: children
        )
    }
}
