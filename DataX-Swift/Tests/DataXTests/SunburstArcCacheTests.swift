import XCTest
@testable import DataX

final class SunburstArcCacheTests: XCTestCase {
    private let innerRadius: CGFloat = 60
    private let maxDepth = 4

    func testArcComputationProducesDeterministicOutput() {
        let root = makeTree()
        let maxRadius: CGFloat = 250

        let first = SunburstView.computeArcs(
            for: root, maxRadius: maxRadius, innerRadius: innerRadius, maxDepth: maxDepth
        )
        let second = SunburstView.computeArcs(
            for: root, maxRadius: maxRadius, innerRadius: innerRadius, maxDepth: maxDepth
        )

        XCTAssertEqual(first.count, second.count)
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertEqual(a.startAngle, b.startAngle, accuracy: 1e-10)
            XCTAssertEqual(a.endAngle, b.endAngle, accuracy: 1e-10)
            XCTAssertEqual(a.innerRadius, b.innerRadius, accuracy: 1e-10)
            XCTAssertEqual(a.outerRadius, b.outerRadius, accuracy: 1e-10)
            XCTAssertEqual(a.depth, b.depth)
        }
    }

    func testArcCountMatchesExpectedForKnownTree() {
        let root = makeTree()
        let maxRadius: CGFloat = 250

        let arcs = SunburstView.computeArcs(
            for: root, maxRadius: maxRadius, innerRadius: innerRadius, maxDepth: maxDepth
        )

        // Tree: root -> [apps(dir, 3000), docs(dir, 2000), readme(file, 500)]
        //   apps -> [xcode(file, 2000), safari(file, 1000)]
        //   docs -> [notes(file, 1500), archive(file, 500)]
        // Depth 0: 3 children (apps, docs, readme) — all > 0.5° of 360° → 3 arcs
        // Depth 1: apps has 2 children, docs has 2 children → 4 arcs
        // Total: 7 arcs
        XCTAssertEqual(arcs.count, 7)
    }

    func testSmallArcsAreCulled() {
        let root = makeDirectory("/root")
        let big = makeFile("/root/big", size: 1_000_000)
        let tiny = makeFile("/root/tiny", size: 1)
        root.children = [big, tiny]

        let arcs = SunburstView.computeArcs(
            for: root, maxRadius: 250, innerRadius: innerRadius, maxDepth: maxDepth
        )

        // tiny's angle span: (1/1_000_001) * 2π ≈ 0.00000628 rad ≈ 0.00036°
        // That's way below 0.5° threshold, so tiny should be culled
        XCTAssertEqual(arcs.count, 1)
        XCTAssertEqual(arcs.first?.node.name, "big")
    }

    func testEmptyRootProducesNoArcs() {
        let root = makeDirectory("/empty")

        let arcs = SunburstView.computeArcs(
            for: root, maxRadius: 250, innerRadius: innerRadius, maxDepth: maxDepth
        )

        XCTAssertTrue(arcs.isEmpty)
    }

    func testArcsRespectMaxDepth() {
        // Create a tree 5 levels deep, maxDepth=4 means only depths 0-3 should appear
        let root = makeDirectory("/root", size: 1000)
        let d1 = makeDirectory("/root/d1", size: 1000)
        let d2 = makeDirectory("/root/d1/d2", size: 1000)
        let d3 = makeDirectory("/root/d1/d2/d3", size: 1000)
        let d4 = makeDirectory("/root/d1/d2/d3/d4", size: 1000)
        let file = makeFile("/root/d1/d2/d3/d4/file", size: 1000)

        d4.children = [file]
        d3.children = [d4]
        d2.children = [d3]
        d1.children = [d2]
        root.children = [d1]

        let arcs = SunburstView.computeArcs(
            for: root, maxRadius: 250, innerRadius: innerRadius, maxDepth: maxDepth
        )

        let maxArcDepth = arcs.map(\.depth).max() ?? -1
        XCTAssertLessThan(maxArcDepth, maxDepth)
    }

    func testMaxArcLimitEnforced() {
        // Build 700 single-child chains, each 3 levels deep: dir → sub-dir → file.
        // Every arc span ≈ 360°/700 ≈ 0.514° (> 0.5° threshold), so none are culled.
        // Without the 2000-arc guard, this tree produces 2100 arcs.
        let chainCount = 700
        let root = makeDirectory("/root", size: UInt64(chainCount * 1000))
        var rootChildren: [FileNode] = []

        for i in 0..<chainCount {
            let dir = makeDirectory("/root/d\(i)", size: 1000)
            let sub = makeDirectory("/root/d\(i)/s", size: 1000)
            let file = makeFile("/root/d\(i)/s/f", size: 1000)
            sub.children = [file]
            dir.children = [sub]
            rootChildren.append(dir)
        }

        root.children = rootChildren

        let arcs = SunburstView.computeArcs(
            for: root, maxRadius: 500, innerRadius: innerRadius, maxDepth: maxDepth
        )

        XCTAssertLessThanOrEqual(arcs.count, 2000,
            "Arc count (\(arcs.count)) should not exceed the 2000 limit")
        XCTAssertGreaterThan(arcs.count, 1500,
            "Arc count should be close to 2000, confirming the guard is actually exercised")
    }

    func testArcLimitDoesNotAffectSmallTrees() {
        // The known 7-arc tree should still produce exactly 7 arcs (no false truncation)
        let root = makeTree()
        let arcs = SunburstView.computeArcs(
            for: root, maxRadius: 250, innerRadius: innerRadius, maxDepth: maxDepth
        )

        XCTAssertEqual(arcs.count, 7,
            "Small tree should produce exactly 7 arcs, not be affected by the 2000 limit")
    }

    // MARK: - Helpers

    private func makeTree() -> FileNode {
        let root = makeDirectory("/root", size: 5500)
        let apps = makeDirectory("/root/Applications", size: 3000)
        let xcode = makeFile("/root/Applications/Xcode", size: 2000)
        let safari = makeFile("/root/Applications/Safari", size: 1000)
        apps.children = [xcode, safari]

        let docs = makeDirectory("/root/Documents", size: 2000)
        let notes = makeFile("/root/Documents/Notes", size: 1500)
        let archive = makeFile("/root/Documents/Archive", size: 500)
        docs.children = [notes, archive]

        let readme = makeFile("/root/readme.txt", size: 500)
        root.children = [apps, docs, readme]
        return root
    }

    private func makeDirectory(_ path: String, size: UInt64 = 0) -> FileNode {
        FileNode(url: URL(fileURLWithPath: path), isDirectory: true, size: size)
    }

    private func makeFile(_ path: String, size: UInt64) -> FileNode {
        FileNode(url: URL(fileURLWithPath: path), isDirectory: false, size: size)
    }
}
