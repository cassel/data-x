import Testing
import Foundation
import GRDB
@testable import DataX

@Suite("LazyFileNode Tests")
struct LazyFileNodeTests {

    // MARK: - Helpers

    private func makeDatabase() throws -> FileTreeDatabase {
        try FileTreeDatabase()
    }

    private let testScanID = UUID()

    private func makeNode(
        path: String = "/Users/test/file.txt",
        name: String = "file.txt",
        size: UInt64 = 1024,
        isDirectory: Bool = false,
        fileCount: Int = 1,
        parentPath: String? = "/Users/test",
        modificationDate: Date? = nil,
        fileExtension: String? = "txt",
        isSymlink: Bool = false,
        isHidden: Bool = false,
        scanID: UUID? = nil
    ) -> LazyFileNode {
        LazyFileNode(
            path: path,
            name: name,
            size: size,
            isDirectory: isDirectory,
            fileCount: fileCount,
            parentPath: parentPath,
            modificationDate: modificationDate,
            fileExtension: fileExtension,
            isSymlink: isSymlink,
            isHidden: isHidden,
            scanID: scanID ?? testScanID
        )
    }

    // MARK: - Insert and Fetch Single Node

    @Test("Insert and fetch single LazyFileNode")
    func testInsertAndFetchSingle() throws {
        let db = try makeDatabase()
        let node = makeNode()

        try db.insert(node)
        let fetched = try db.fetchByPath("/Users/test/file.txt")

        #expect(fetched != nil)
        #expect(fetched?.path == "/Users/test/file.txt")
        #expect(fetched?.name == "file.txt")
        #expect(fetched?.size == 1024)
        #expect(fetched?.isDirectory == false)
        #expect(fetched?.fileCount == 1)
        #expect(fetched?.parentPath == "/Users/test")
        #expect(fetched?.fileExtension == "txt")
        #expect(fetched?.isSymlink == false)
        #expect(fetched?.isHidden == false)
        #expect(fetched?.scanID == testScanID)
    }

    // MARK: - Batch Insert

    @Test("Batch insert of 1000+ nodes")
    func testBatchInsert() throws {
        let db = try makeDatabase()
        let parentPath = "/Users/test/bigdir"

        // Create parent directory node
        let parent = makeNode(
            path: parentPath,
            name: "bigdir",
            size: 0,
            isDirectory: true,
            fileCount: 0,
            parentPath: "/Users/test"
        )
        try db.insert(parent)

        // Create 1500 child nodes
        var nodes: [LazyFileNode] = []
        for i in 0..<1500 {
            nodes.append(makeNode(
                path: "\(parentPath)/file\(i).dat",
                name: "file\(i).dat",
                size: UInt64(i * 100),
                isDirectory: false,
                fileCount: 1,
                parentPath: parentPath,
                fileExtension: "dat"
            ))
        }

        try db.insertBatch(nodes)

        let count = try db.childrenCount(of: parentPath)
        #expect(count == 1500)
    }

    // MARK: - Fetch Children with Pagination

    @Test("fetchChildren with pagination (limit/offset)")
    func testFetchChildrenPagination() throws {
        let db = try makeDatabase()
        let parentPath = "/Users/test/dir"

        // Insert 10 children with different sizes
        var nodes: [LazyFileNode] = []
        for i in 0..<10 {
            nodes.append(makeNode(
                path: "\(parentPath)/file\(i).txt",
                name: "file\(i).txt",
                size: UInt64((9 - i) * 1000), // 9000, 8000, ..., 0
                parentPath: parentPath,
                fileExtension: "txt"
            ))
        }
        try db.insertBatch(nodes)

        // First page: 3 items
        let page1 = try db.fetchChildren(of: parentPath, limit: 3, offset: 0)
        #expect(page1.count == 3)

        // Second page: 3 items
        let page2 = try db.fetchChildren(of: parentPath, limit: 3, offset: 3)
        #expect(page2.count == 3)

        // Verify no overlap
        let page1Paths = Set(page1.map(\.path))
        let page2Paths = Set(page2.map(\.path))
        #expect(page1Paths.isDisjoint(with: page2Paths))
    }

    // MARK: - Fetch Children Sorted by Size DESC

    @Test("fetchChildren returns sorted by size DESC")
    func testFetchChildrenSortedBySizeDesc() throws {
        let db = try makeDatabase()
        let parentPath = "/Users/test/sorted"

        let nodes = [
            makeNode(path: "\(parentPath)/small.txt", name: "small.txt", size: 100, parentPath: parentPath),
            makeNode(path: "\(parentPath)/medium.txt", name: "medium.txt", size: 5000, parentPath: parentPath),
            makeNode(path: "\(parentPath)/large.txt", name: "large.txt", size: 50000, parentPath: parentPath),
            makeNode(path: "\(parentPath)/tiny.txt", name: "tiny.txt", size: 10, parentPath: parentPath),
        ]
        try db.insertBatch(nodes)

        let children = try db.fetchChildren(of: parentPath)

        #expect(children.count == 4)
        #expect(children[0].size == 50000)
        #expect(children[1].size == 5000)
        #expect(children[2].size == 100)
        #expect(children[3].size == 10)
    }

    // MARK: - Children Count

    @Test("childrenCount returns correct count")
    func testChildrenCount() throws {
        let db = try makeDatabase()
        let parentPath = "/Users/test/countdir"

        let nodes = (0..<5).map { i in
            makeNode(
                path: "\(parentPath)/file\(i).txt",
                name: "file\(i).txt",
                parentPath: parentPath
            )
        }
        try db.insertBatch(nodes)

        let count = try db.childrenCount(of: parentPath)
        #expect(count == 5)

        // Non-existent parent should return 0
        let emptyCount = try db.childrenCount(of: "/nonexistent")
        #expect(emptyCount == 0)
    }

    // MARK: - toFileNode Adapter

    @Test("toFileNode adapter produces valid FileNode tree")
    func testToFileNodeAdapter() throws {
        let db = try makeDatabase()
        let rootPath = "/Users/test/root"

        // Create root directory
        let root = makeNode(
            path: rootPath,
            name: "root",
            size: 3000,
            isDirectory: true,
            fileCount: 3,
            parentPath: nil
        )
        try db.insert(root)

        // Create children
        let children = [
            makeNode(path: "\(rootPath)/big.dat", name: "big.dat", size: 2000, parentPath: rootPath, fileExtension: "dat"),
            makeNode(path: "\(rootPath)/small.dat", name: "small.dat", size: 1000, parentPath: rootPath, fileExtension: "dat"),
        ]
        try db.insertBatch(children)

        // Convert to FileNode
        let fileNode = try root.toFileNode(provider: db, maxDepth: 2)

        #expect(fileNode.isDirectory == true)
        #expect(fileNode.path == URL(fileURLWithPath: rootPath))
        #expect(fileNode.fileCount == 3)
        #expect(fileNode.children?.count == 2)
        // Children should be sorted by size DESC
        #expect(fileNode.children?[0].size == 2000)
        #expect(fileNode.children?[1].size == 1000)
    }

    // MARK: - Delete All by Scan ID

    @Test("deleteAll(scanID:) cleans up correctly")
    func testDeleteAllByScanID() throws {
        let db = try makeDatabase()
        let scanA = UUID()
        let scanB = UUID()

        // Insert nodes for two different scans
        let nodesA = [
            makeNode(path: "/a/file1.txt", name: "file1.txt", parentPath: "/a", scanID: scanA),
            makeNode(path: "/a/file2.txt", name: "file2.txt", parentPath: "/a", scanID: scanA),
        ]
        let nodesB = [
            makeNode(path: "/b/file1.txt", name: "file1.txt", parentPath: "/b", scanID: scanB),
        ]
        try db.insertBatch(nodesA)
        try db.insertBatch(nodesB)

        // Delete scan A
        try db.deleteAll(scanID: scanA)

        // Scan A nodes should be gone
        #expect(try db.fetchByPath("/a/file1.txt") == nil)
        #expect(try db.fetchByPath("/a/file2.txt") == nil)

        // Scan B node should still exist
        #expect(try db.fetchByPath("/b/file1.txt") != nil)
    }

    // MARK: - In-Memory Database Isolation

    @Test("In-memory database provides test isolation")
    func testInMemoryIsolation() throws {
        let db1 = try makeDatabase()
        let db2 = try makeDatabase()

        try db1.insert(makeNode(path: "/db1/file.txt", name: "file.txt", parentPath: "/db1"))

        // db2 should not see db1's data
        #expect(try db2.fetchByPath("/db1/file.txt") == nil)
    }

    // MARK: - Root Node via Provider

    @Test("Provider root returns node with nil parentPath")
    func testProviderRoot() throws {
        let db = try makeDatabase()
        let scanID = UUID()

        let root = makeNode(
            path: "/Users/test",
            name: "test",
            size: 10000,
            isDirectory: true,
            fileCount: 10,
            parentPath: nil,
            scanID: scanID
        )
        try db.insert(root)

        let foundRoot = try db.root(scanID: scanID)
        #expect(foundRoot != nil)
        #expect(foundRoot?.path == "/Users/test")
        #expect(foundRoot?.parentPath == nil)
    }

    // MARK: - Computed Properties

    @Test("Computed properties reuse existing utilities")
    func testComputedProperties() {
        let node = makeNode(fileExtension: "pdf")
        #expect(node.category == .documents)
        #expect(node.formattedSize.isEmpty == false)

        let dirNode = makeNode(fileExtension: nil, isSymlink: false)
        #expect(dirNode.category == .other)
    }

    // MARK: - Identifiable and Hashable

    @Test("Identifiable uses path as id")
    func testIdentifiable() {
        let node = makeNode(path: "/test/path")
        #expect(node.id == "/test/path")
    }

    @Test("Hashable and Equatable via path")
    func testHashableEquatable() {
        let node1 = makeNode(path: "/same/path", name: "a")
        let node2 = makeNode(path: "/same/path", name: "b")
        let node3 = makeNode(path: "/different/path")

        #expect(node1 == node2)
        #expect(node1 != node3)

        var set: Set<LazyFileNode> = [node1, node2]
        #expect(set.count == 1)
        set.insert(node3)
        #expect(set.count == 2)
    }

    // MARK: - toFileNode Depth Limiting

    @Test("toFileNode respects maxDepth")
    func testToFileNodeMaxDepth() throws {
        let db = try makeDatabase()

        // Create 3-level tree: root → dir → file
        let root = makeNode(path: "/root", name: "root", size: 100, isDirectory: true, fileCount: 1, parentPath: nil)
        let dir = makeNode(path: "/root/dir", name: "dir", size: 100, isDirectory: true, fileCount: 1, parentPath: "/root")
        let file = makeNode(path: "/root/dir/file.txt", name: "file.txt", size: 100, parentPath: "/root/dir")

        try db.insert(root)
        try db.insert(dir)
        try db.insert(file)

        // maxDepth=1 should only load one level of children
        let shallow = try root.toFileNode(provider: db, maxDepth: 1)
        #expect(shallow.children?.count == 1) // dir
        #expect(shallow.children?[0].children == nil || shallow.children?[0].children?.isEmpty == true)

        // maxDepth=2 should load both levels
        let deep = try root.toFileNode(provider: db, maxDepth: 2)
        #expect(deep.children?.count == 1)
        #expect(deep.children?[0].children?.count == 1)
    }
}
