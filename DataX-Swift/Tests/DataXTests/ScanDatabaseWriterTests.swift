import Testing
import Foundation
@testable import DataX

@Suite("ScanDatabaseWriter Tests")
struct ScanDatabaseWriterTests {

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
        fileExtension: String? = "txt",
        scanID: UUID? = nil
    ) -> LazyFileNode {
        LazyFileNode(
            path: path,
            name: name,
            size: size,
            isDirectory: isDirectory,
            fileCount: fileCount,
            parentPath: parentPath,
            modificationDate: nil,
            fileExtension: fileExtension,
            isSymlink: false,
            isHidden: false,
            scanID: scanID ?? testScanID
        )
    }

    // MARK: - Batch Insertion

    @Test("Batch insertion: add 2500 nodes, verify all in database")
    func testBatchInsertion2500Nodes() throws {
        let db = try makeDatabase()
        let writer = ScanDatabaseWriter(database: db)

        for i in 0..<2500 {
            writer.add(makeNode(
                path: "/test/file\(i).txt",
                name: "file\(i).txt",
                size: UInt64(i),
                parentPath: "/test"
            ))
        }
        try writer.flush()

        let count = try db.childrenCount(of: "/test")
        #expect(count == 2500)
    }

    // MARK: - Flush Triggers at Boundary

    @Test("Flush triggers at 1000-node boundary")
    func testFlushTriggersAtBoundary() throws {
        let db = try makeDatabase()
        let writer = ScanDatabaseWriter(database: db)

        // Add exactly 1000 nodes — should auto-flush
        for i in 0..<1000 {
            writer.add(makeNode(
                path: "/test/file\(i).txt",
                name: "file\(i).txt",
                parentPath: "/test"
            ))
        }

        // Without calling flush(), 1000 nodes should already be in the database
        let count = try db.childrenCount(of: "/test")
        #expect(count == 1000)
    }

    // MARK: - Finalize Flushes Remaining Buffer

    @Test("Finalize flushes remaining buffer")
    func testFinalizeFlushesRemainingBuffer() throws {
        let db = try makeDatabase()
        let writer = ScanDatabaseWriter(database: db)

        // Add 500 nodes (less than batch size)
        for i in 0..<500 {
            writer.add(makeNode(
                path: "/test/file\(i).txt",
                name: "file\(i).txt",
                parentPath: "/test"
            ))
        }

        // Before finalize, nodes might not be flushed yet (buffer < 1000)
        // After finalize, all should be in the database
        try writer.finalize(scanID: testScanID)

        let count = try db.childrenCount(of: "/test")
        #expect(count == 500)
    }

    // MARK: - Size Aggregation: 3-Level Tree

    @Test("Size aggregation: 3-level tree with correct directory sizes")
    func testSizeAggregation3LevelTree() throws {
        let db = try makeDatabase()
        let writer = ScanDatabaseWriter(database: db)

        // root → dirA → file1 (100), file2 (200)
        //      → dirB → file3 (300)
        writer.add(makeNode(path: "/root", name: "root", size: 0, isDirectory: true, fileCount: 0, parentPath: nil))
        writer.add(makeNode(path: "/root/dirA", name: "dirA", size: 0, isDirectory: true, fileCount: 0, parentPath: "/root"))
        writer.add(makeNode(path: "/root/dirB", name: "dirB", size: 0, isDirectory: true, fileCount: 0, parentPath: "/root"))
        writer.add(makeNode(path: "/root/dirA/file1.txt", name: "file1.txt", size: 100, parentPath: "/root/dirA"))
        writer.add(makeNode(path: "/root/dirA/file2.txt", name: "file2.txt", size: 200, parentPath: "/root/dirA"))
        writer.add(makeNode(path: "/root/dirB/file3.txt", name: "file3.txt", size: 300, parentPath: "/root/dirB"))

        try writer.finalize(scanID: testScanID)

        let dirA = try db.fetchByPath("/root/dirA")
        #expect(dirA?.size == 300) // 100 + 200
        #expect(dirA?.fileCount == 2)

        let dirB = try db.fetchByPath("/root/dirB")
        #expect(dirB?.size == 300)
        #expect(dirB?.fileCount == 1)

        let root = try db.fetchByPath("/root")
        #expect(root?.size == 600) // 300 + 300
        #expect(root?.fileCount == 3)
    }

    // MARK: - Size Aggregation: Deeply Nested (5+ Levels)

    @Test("Size aggregation with deeply nested dirs (5+ levels)")
    func testSizeAggregationDeeplyNested() throws {
        let db = try makeDatabase()
        let writer = ScanDatabaseWriter(database: db)

        // Create 6-level deep tree: /a/b/c/d/e/f/file.txt (size=42)
        let paths = ["/a", "/a/b", "/a/b/c", "/a/b/c/d", "/a/b/c/d/e", "/a/b/c/d/e/f"]
        writer.add(makeNode(path: "/a", name: "a", size: 0, isDirectory: true, fileCount: 0, parentPath: nil))
        for i in 1..<paths.count {
            writer.add(makeNode(
                path: paths[i],
                name: URL(fileURLWithPath: paths[i]).lastPathComponent,
                size: 0,
                isDirectory: true,
                fileCount: 0,
                parentPath: paths[i - 1]
            ))
        }
        writer.add(makeNode(
            path: "/a/b/c/d/e/f/file.txt",
            name: "file.txt",
            size: 42,
            parentPath: "/a/b/c/d/e/f"
        ))

        try writer.finalize(scanID: testScanID)

        // Every directory up to root should have size=42, fileCount=1
        for path in paths {
            let dir = try db.fetchByPath(path)
            #expect(dir?.size == 42, "Expected size 42 at \(path), got \(dir?.size ?? 0)")
            #expect(dir?.fileCount == 1, "Expected fileCount 1 at \(path), got \(dir?.fileCount ?? 0)")
        }
    }

    // MARK: - Size Aggregation: Empty Directories

    @Test("Size aggregation with empty directories (size should be 0)")
    func testSizeAggregationEmptyDirectories() throws {
        let db = try makeDatabase()
        let writer = ScanDatabaseWriter(database: db)

        writer.add(makeNode(path: "/root", name: "root", size: 0, isDirectory: true, fileCount: 0, parentPath: nil))
        writer.add(makeNode(path: "/root/empty", name: "empty", size: 0, isDirectory: true, fileCount: 0, parentPath: "/root"))

        try writer.finalize(scanID: testScanID)

        let emptyDir = try db.fetchByPath("/root/empty")
        #expect(emptyDir?.size == 0)
        #expect(emptyDir?.fileCount == 0)

        let root = try db.fetchByPath("/root")
        #expect(root?.size == 0)
        #expect(root?.fileCount == 0)
    }

    // MARK: - fileCount Aggregation

    @Test("fileCount aggregation for directories")
    func testFileCountAggregation() throws {
        let db = try makeDatabase()
        let writer = ScanDatabaseWriter(database: db)

        // root → dir → 5 files
        writer.add(makeNode(path: "/root", name: "root", size: 0, isDirectory: true, fileCount: 0, parentPath: nil))
        writer.add(makeNode(path: "/root/dir", name: "dir", size: 0, isDirectory: true, fileCount: 0, parentPath: "/root"))
        for i in 0..<5 {
            writer.add(makeNode(
                path: "/root/dir/f\(i).txt",
                name: "f\(i).txt",
                size: 10,
                fileCount: 1,
                parentPath: "/root/dir"
            ))
        }

        try writer.finalize(scanID: testScanID)

        let dir = try db.fetchByPath("/root/dir")
        #expect(dir?.fileCount == 5)

        let root = try db.fetchByPath("/root")
        #expect(root?.fileCount == 5)
    }

    // MARK: - fromScanEntry Conversion

    @Test("LazyFileNode.fromScanEntry() conversion correctness")
    func testFromScanEntryConversion() {
        let scanID = UUID()

        // Test file conversion
        let fileURL = URL(fileURLWithPath: "/Users/test/Documents/photo.JPG")
        let fileNode = LazyFileNode.fromScanEntry(
            url: fileURL,
            isDirectory: false,
            isSymlink: false,
            fileSize: 5000,
            modificationDate: Date(timeIntervalSince1970: 1000),
            scanID: scanID
        )

        #expect(fileNode.path == fileURL.standardizedFileURL.path)
        #expect(fileNode.name == "photo.JPG")
        #expect(fileNode.size == 5000)
        #expect(fileNode.isDirectory == false)
        #expect(fileNode.fileCount == 1)
        #expect(fileNode.parentPath == URL(fileURLWithPath: "/Users/test/Documents").standardizedFileURL.path)
        #expect(fileNode.fileExtension == "jpg")
        #expect(fileNode.isHidden == false)
        #expect(fileNode.scanID == scanID)

        // Test directory conversion
        let dirURL = URL(fileURLWithPath: "/Users/test/.hidden_dir")
        let dirNode = LazyFileNode.fromScanEntry(
            url: dirURL,
            isDirectory: true,
            isSymlink: false,
            fileSize: 4096,
            modificationDate: nil,
            scanID: scanID
        )

        #expect(dirNode.size == 0) // dirs get 0, aggregated post-scan
        #expect(dirNode.isDirectory == true)
        #expect(dirNode.fileCount == 0)
        #expect(dirNode.fileExtension == nil)
        #expect(dirNode.isHidden == true)

        // Test file with no extension
        let noExtURL = URL(fileURLWithPath: "/Users/test/Makefile")
        let noExtNode = LazyFileNode.fromScanEntry(
            url: noExtURL,
            isDirectory: false,
            isSymlink: false,
            fileSize: 100,
            modificationDate: nil,
            scanID: scanID
        )
        #expect(noExtNode.fileExtension == nil)

        // Test symlink
        let symlinkURL = URL(fileURLWithPath: "/Users/test/link.txt")
        let symlinkNode = LazyFileNode.fromScanEntry(
            url: symlinkURL,
            isDirectory: false,
            isSymlink: true,
            fileSize: 50,
            modificationDate: nil,
            scanID: scanID
        )
        #expect(symlinkNode.isSymlink == true)
    }

    // MARK: - beginScan Cleans Previous Data

    @Test("beginScan cleans all previous data")
    func testBeginScanCleansPreviousData() throws {
        let db = try makeDatabase()
        let scanID = UUID()
        let writer = ScanDatabaseWriter(database: db)

        // Insert data for one scanID
        try db.insertBatch([
            makeNode(path: "/old/file1.txt", name: "file1.txt", parentPath: "/old", scanID: scanID),
            makeNode(path: "/old/file2.txt", name: "file2.txt", parentPath: "/old", scanID: scanID),
        ])

        // Insert data for a different scanID
        let otherScanID = UUID()
        try db.insert(makeNode(path: "/other/file.txt", name: "file.txt", parentPath: "/other", scanID: otherScanID))

        // Verify data exists
        #expect(try db.fetchByPath("/old/file1.txt") != nil)
        #expect(try db.fetchByPath("/other/file.txt") != nil)

        // beginScan should clean ALL data to prevent PK conflicts on re-scan
        let newScanID = UUID()
        try writer.beginScan(scanID: newScanID, rootPath: "/new")

        // All previous data should be gone
        #expect(try db.fetchByPath("/old/file1.txt") == nil)
        #expect(try db.fetchByPath("/old/file2.txt") == nil)
        #expect(try db.fetchByPath("/other/file.txt") == nil)
    }

    // MARK: - In-Memory Database Isolation

    @Test("In-memory GRDB database for test isolation")
    func testInMemoryDatabaseIsolation() throws {
        let db1 = try makeDatabase()
        let db2 = try makeDatabase()
        let writer1 = ScanDatabaseWriter(database: db1)
        let writer2 = ScanDatabaseWriter(database: db2)

        writer1.add(makeNode(path: "/db1/file.txt", name: "file.txt", parentPath: "/db1"))
        try writer1.flush()

        writer2.add(makeNode(path: "/db2/file.txt", name: "file.txt", parentPath: "/db2"))
        try writer2.flush()

        // Each database should only see its own data
        #expect(try db1.fetchByPath("/db1/file.txt") != nil)
        #expect(try db1.fetchByPath("/db2/file.txt") == nil)
        #expect(try db2.fetchByPath("/db2/file.txt") != nil)
        #expect(try db2.fetchByPath("/db1/file.txt") == nil)
    }
}
