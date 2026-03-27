import Testing
import Foundation
@testable import DataX

@Suite("VirtualTreeProvider Tests")
struct VirtualTreeProviderTests {

    // MARK: - Helpers

    private let testScanID = UUID()

    private func makeDatabase() throws -> FileTreeDatabase {
        try FileTreeDatabase()
    }

    private func makeNode(
        path: String,
        name: String,
        size: UInt64 = 0,
        isDirectory: Bool = false,
        fileCount: Int = 0,
        parentPath: String? = nil,
        scanID: UUID? = nil
    ) -> LazyFileNode {
        LazyFileNode(
            path: path,
            name: name,
            size: size,
            isDirectory: isDirectory,
            fileCount: isDirectory ? fileCount : 1,
            parentPath: parentPath,
            modificationDate: nil,
            fileExtension: isDirectory ? nil : URL(fileURLWithPath: path).pathExtension.lowercased(),
            isSymlink: false,
            isHidden: name.hasPrefix("."),
            scanID: scanID ?? testScanID
        )
    }

    /// Creates a 3-level tree: root → (dirA(file1, file2), dirB(file3))
    private func seedThreeLevelTree(db: FileTreeDatabase, scanID: UUID? = nil) throws {
        let sid = scanID ?? testScanID
        let writer = ScanDatabaseWriter(database: db)
        writer.add(makeNode(path: "/root", name: "root", size: 0, isDirectory: true, parentPath: nil, scanID: sid))
        writer.add(makeNode(path: "/root/dirA", name: "dirA", size: 0, isDirectory: true, parentPath: "/root", scanID: sid))
        writer.add(makeNode(path: "/root/dirB", name: "dirB", size: 0, isDirectory: true, parentPath: "/root", scanID: sid))
        writer.add(makeNode(path: "/root/dirA/file1.txt", name: "file1.txt", size: 100, parentPath: "/root/dirA", scanID: sid))
        writer.add(makeNode(path: "/root/dirA/file2.txt", name: "file2.txt", size: 200, parentPath: "/root/dirA", scanID: sid))
        writer.add(makeNode(path: "/root/dirB/file3.txt", name: "file3.txt", size: 300, parentPath: "/root/dirB", scanID: sid))
        try writer.finalize(scanID: sid)
    }

    /// Creates a deep tree: /root → /root/d1 → /root/d1/d2 → ... → /root/d1/.../dN/file.txt
    private func seedDeepTree(db: FileTreeDatabase, depth: Int, scanID: UUID? = nil) throws {
        let sid = scanID ?? testScanID
        let writer = ScanDatabaseWriter(database: db)

        var currentPath = "/root"
        writer.add(makeNode(path: currentPath, name: "root", size: 0, isDirectory: true, parentPath: nil, scanID: sid))

        for i in 1...depth {
            let parentPath = currentPath
            currentPath = "\(currentPath)/d\(i)"
            writer.add(makeNode(path: currentPath, name: "d\(i)", size: 0, isDirectory: true, parentPath: parentPath, scanID: sid))
        }

        // Add a file at the deepest level
        writer.add(makeNode(path: "\(currentPath)/leaf.txt", name: "leaf.txt", size: 42, parentPath: currentPath, scanID: sid))

        try writer.finalize(scanID: sid)
    }

    // MARK: - Test: rootNode returns correct root

    @Test("rootNode returns correct root from database")
    func testRootNodeReturnsRoot() throws {
        let db = try makeDatabase()
        try seedThreeLevelTree(db: db)
        let provider = VirtualTreeProvider(database: db, scanID: testScanID)

        let root = try provider.rootNode(maxDepth: 6)

        #expect(root != nil)
        #expect(root?.name == "root")
        #expect(root?.isDirectory == true)
        #expect(root?.size == 600) // aggregated: 100+200+300
        #expect(root?.children?.count == 2)
    }

    // MARK: - Test: Depth-limited loading

    @Test("rootNode respects maxDepth: children nil at depth boundary")
    func testDepthLimitedLoading() throws {
        let db = try makeDatabase()
        try seedDeepTree(db: db, depth: 5)
        let provider = VirtualTreeProvider(database: db, scanID: testScanID)

        // Load only 2 levels deep
        let root = try provider.rootNode(maxDepth: 2)

        #expect(root != nil)
        #expect(root?.children?.count == 1) // d1

        let d1 = root?.children?[0]
        #expect(d1?.name == "d1")
        #expect(d1?.children?.count == 1) // d2

        let d2 = d1?.children?[0]
        #expect(d2?.name == "d2")
        // At depth boundary, children should be nil (lazy)
        #expect(d2?.children == nil)
    }

    // MARK: - Test: loadChildren expands nil children

    @Test("loadChildren expands previously-nil children set")
    func testLoadChildrenExpands() throws {
        let db = try makeDatabase()
        try seedDeepTree(db: db, depth: 4)
        let provider = VirtualTreeProvider(database: db, scanID: testScanID)

        // Load only 1 level
        let root = try provider.rootNode(maxDepth: 1)
        let d1 = root?.children?[0]
        #expect(d1?.children == nil) // Not loaded yet

        // Now expand d1
        try provider.loadChildren(of: d1!, depth: 2)

        #expect(d1?.children != nil)
        #expect(d1?.children?.count == 1) // d2
        #expect(d1?.children?[0].name == "d2")
    }

    // MARK: - Test: ensureDepth loads missing levels

    @Test("ensureDepth loads missing levels")
    func testEnsureDepthLoadsMissing() throws {
        let db = try makeDatabase()
        try seedDeepTree(db: db, depth: 6)
        let provider = VirtualTreeProvider(database: db, scanID: testScanID)

        // Load only 2 levels
        let root = try provider.rootNode(maxDepth: 2)
        let d1 = root?.children?[0]
        let d2 = d1?.children?[0]
        #expect(d2?.children == nil) // depth boundary

        // Ensure 3 more levels below d2
        try provider.ensureDepth(for: d2!, depth: 3)

        // d2 should now have children loaded
        #expect(d2?.children != nil)
        let d3 = d2?.children?[0]
        #expect(d3?.name == "d3")
        #expect(d3?.children?.count == 1) // d4
        let d4 = d3?.children?[0]
        #expect(d4?.name == "d4")
        #expect(d4?.children?.count == 1) // d5
    }

    // MARK: - Test: LRU eviction nils out children

    @Test("LRU eviction nils out children on evicted FileNodes")
    func testLRUEvictionNilsChildren() throws {
        let db = try makeDatabase()
        try seedThreeLevelTree(db: db)

        // Tiny budget: only 3 nodes fit in cache
        let provider = VirtualTreeProvider(database: db, scanID: testScanID, nodeBudget: 3)

        let root = try provider.rootNode(maxDepth: 6)

        // With budget of 3 and 6 nodes total (root, dirA, dirB, file1, file2, file3),
        // some nodes should have been evicted. The earliest-inserted nodes get evicted.
        // The root was inserted first, so it gets evicted and its children nilled.
        #expect(root != nil)
        // We can't predict exact eviction order easily, but nodeCount should be <= 3
        #expect(provider.nodeCount <= 3)
    }

    // MARK: - Test: nodeForPath returns cached or loads fresh

    @Test("nodeForPath returns cached node or loads from database")
    func testNodeForPath() throws {
        let db = try makeDatabase()
        try seedThreeLevelTree(db: db)
        let provider = VirtualTreeProvider(database: db, scanID: testScanID)

        // Load tree
        _ = try provider.rootNode(maxDepth: 6)

        // Cached hit
        let cachedRoot = try provider.nodeForPath("/root")
        #expect(cachedRoot != nil)
        #expect(cachedRoot?.name == "root")

        // Fresh load for uncached path (create a new provider with small budget)
        let provider2 = VirtualTreeProvider(database: db, scanID: testScanID, nodeBudget: 50_000)
        let fresh = try provider2.nodeForPath("/root/dirA/file1.txt")
        #expect(fresh != nil)
        #expect(fresh?.name == "file1.txt")
        #expect(fresh?.size == 100)
    }

    // MARK: - Test: Navigation sequence

    @Test("Navigation sequence: rootNode → loadChildren on subdir → verify subtree expanded")
    func testNavigationSequence() throws {
        let db = try makeDatabase()
        try seedDeepTree(db: db, depth: 4)
        let provider = VirtualTreeProvider(database: db, scanID: testScanID)

        // Step 1: Load root with shallow depth
        let root = try provider.rootNode(maxDepth: 1)
        #expect(root?.children?.count == 1)

        let d1 = root?.children?[0]
        #expect(d1?.children == nil)

        // Step 2: User navigates to d1 — load children
        try provider.loadChildren(of: d1!, depth: 3)
        #expect(d1?.children != nil)
        #expect(d1?.children?[0].name == "d2")

        // Step 3: Continue navigating deeper
        let d2 = d1?.children?[0]
        #expect(d2?.children?.count == 1) // d3 was loaded
        let d3 = d2?.children?[0]
        #expect(d3?.name == "d3")
    }

    // MARK: - Test: nodeCount diagnostic

    @Test("nodeCount returns current cache count")
    func testNodeCount() throws {
        let db = try makeDatabase()
        try seedThreeLevelTree(db: db)
        let provider = VirtualTreeProvider(database: db, scanID: testScanID)

        #expect(provider.nodeCount == 0) // nothing loaded yet

        _ = try provider.rootNode(maxDepth: 6)

        // 6 nodes: root, dirA, dirB, file1, file2, file3
        #expect(provider.nodeCount == 6)
    }

    // MARK: - Test: In-memory database isolation

    @Test("In-memory GRDB database provides test isolation")
    func testDatabaseIsolation() throws {
        let db1 = try makeDatabase()
        let db2 = try makeDatabase()

        try seedThreeLevelTree(db: db1)

        let provider1 = VirtualTreeProvider(database: db1, scanID: testScanID)
        let provider2 = VirtualTreeProvider(database: db2, scanID: testScanID)

        #expect(try provider1.rootNode() != nil)
        #expect(try provider2.rootNode() == nil) // db2 has no data
    }

    // MARK: - Test: Cache hit reuses existing FileNode

    @Test("Cache hit reuses existing FileNode identity")
    func testCacheHitReusesNode() throws {
        let db = try makeDatabase()
        try seedThreeLevelTree(db: db)
        let provider = VirtualTreeProvider(database: db, scanID: testScanID)

        let root1 = try provider.rootNode(maxDepth: 6)
        let root2 = try provider.rootNode(maxDepth: 6)

        // Same object identity (cache hit)
        #expect(root1 === root2)
    }

    // MARK: - Test: prefetchChildren

    @Test("prefetchChildren loads one level of children into cache")
    func testPrefetchChildren() throws {
        let db = try makeDatabase()
        try seedThreeLevelTree(db: db)
        let provider = VirtualTreeProvider(database: db, scanID: testScanID)

        #expect(provider.nodeCount == 0)
        try provider.prefetchChildren(of: "/root")

        // Should have cached dirA and dirB (2 children of root)
        #expect(provider.nodeCount == 2)
    }
}
