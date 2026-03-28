import XCTest
@testable import DataX

final class ScannerServiceDatabaseTests: XCTestCase {

    // MARK: - Test 7.1: scanToDatabase writes all entries to DB

    func testScanToDatabaseWritesAllEntriesToDatabase() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let alpha = directory.appendingPathComponent("alpha", isDirectory: true)
        let nested = alpha.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(at: alpha.appendingPathComponent("a.txt"), size: 10)
        try writeFile(at: nested.appendingPathComponent("b.bin"), size: 20)
        try writeFile(at: directory.appendingPathComponent("visible.log"), size: 5)

        let db = try FileTreeDatabase()
        let writer = ScanDatabaseWriter(database: db)
        let scanID = UUID()
        try writer.beginScan(scanID: scanID, rootPath: directory.standardizedFileURL.path)

        let scanner = ScannerService()
        let events = await scanner.scanToDatabase(directory: directory, scanID: scanID, databaseWriter: writer)
        _ = await collectEvents(from: events)

        // After scanToDatabase + finalize, all nodes should be in DB
        let root = try XCTUnwrap(db.root(scanID: scanID))
        XCTAssertTrue(root.isDirectory)
        XCTAssertEqual(root.path, directory.standardizedFileURL.path)

        let rootChildren = try db.fetchChildren(of: root.path)
        XCTAssertEqual(rootChildren.count, 2) // alpha dir + visible.log

        let alphaNode = try XCTUnwrap(rootChildren.first(where: { $0.name == "alpha" }))
        XCTAssertTrue(alphaNode.isDirectory)

        let alphaChildren = try db.fetchChildren(of: alphaNode.path)
        // alpha has: a.txt + nested dir
        XCTAssertEqual(alphaChildren.count, 2)
    }

    // MARK: - Test 7.2: scanToDatabase emits correct events

    func testScanToDatabaseEmitsProgressAndDatabaseCompleteOnly() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeFile(at: directory.appendingPathComponent("file1.txt"), size: 10)
        try writeFile(at: directory.appendingPathComponent("file2.txt"), size: 20)

        let db = try FileTreeDatabase()
        let writer = ScanDatabaseWriter(database: db)
        let scanID = UUID()
        try writer.beginScan(scanID: scanID, rootPath: directory.standardizedFileURL.path)

        let scanner = ScannerService()
        let events = await scanner.scanToDatabase(directory: directory, scanID: scanID, databaseWriter: writer)
        let collectedEvents = await collectEvents(from: events)

        // Should have progress events
        let progressEvents = collectedEvents.filter { if case .progress = $0 { return true }; return false }
        XCTAssertFalse(progressEvents.isEmpty, "Should emit progress events")

        // Should have exactly one databaseComplete event
        let dbCompleteEvents = collectedEvents.filter { if case .databaseComplete = $0 { return true }; return false }
        XCTAssertEqual(dbCompleteEvents.count, 1, "Should emit exactly one .databaseComplete event")

        // Should NOT have partialTree events
        let partialTreeEvents = collectedEvents.filter { if case .partialTree = $0 { return true }; return false }
        XCTAssertTrue(partialTreeEvents.isEmpty, "Should NOT emit .partialTree events")

        // Should NOT have complete events
        let completeEvents = collectedEvents.filter { if case .complete = $0 { return true }; return false }
        XCTAssertTrue(completeEvents.isEmpty, "Should NOT emit .complete events")
    }

    // MARK: - Test 7.3: quickAggregateSizes correctly sums child sizes

    func testQuickAggregateSizesCorrectlySumsOneLevel() throws {
        let db = try FileTreeDatabase()
        let scanID = UUID()

        // Insert root directory
        try db.insert(LazyFileNode(
            path: "/root",
            name: "root",
            size: 0,
            isDirectory: true,
            fileCount: 0,
            parentPath: nil,
            modificationDate: nil,
            fileExtension: nil,
            isSymlink: false,
            isHidden: false,
            scanID: scanID
        ))

        // Insert child directory "alpha" with initial size 0
        try db.insert(LazyFileNode(
            path: "/root/alpha",
            name: "alpha",
            size: 0,
            isDirectory: true,
            fileCount: 0,
            parentPath: "/root",
            modificationDate: nil,
            fileExtension: nil,
            isSymlink: false,
            isHidden: false,
            scanID: scanID
        ))

        // Insert files under alpha
        try db.insert(LazyFileNode(
            path: "/root/alpha/a.txt",
            name: "a.txt",
            size: 100,
            isDirectory: false,
            fileCount: 1,
            parentPath: "/root/alpha",
            modificationDate: nil,
            fileExtension: "txt",
            isSymlink: false,
            isHidden: false,
            scanID: scanID
        ))

        try db.insert(LazyFileNode(
            path: "/root/alpha/b.txt",
            name: "b.txt",
            size: 200,
            isDirectory: false,
            fileCount: 1,
            parentPath: "/root/alpha",
            modificationDate: nil,
            fileExtension: "txt",
            isSymlink: false,
            isHidden: false,
            scanID: scanID
        ))

        // Insert a standalone file under root
        try db.insert(LazyFileNode(
            path: "/root/c.log",
            name: "c.log",
            size: 50,
            isDirectory: false,
            fileCount: 1,
            parentPath: "/root",
            modificationDate: nil,
            fileExtension: "log",
            isSymlink: false,
            isHidden: false,
            scanID: scanID
        ))

        // Quick aggregate: only top-level dirs under "/root"
        try db.quickAggregateSizes(scanID: scanID, parentPath: "/root")

        // alpha should now have size = 300 (100 + 200) and fileCount = 2
        let alpha = try XCTUnwrap(db.fetchByPath("/root/alpha"))
        XCTAssertEqual(alpha.size, 300)
        XCTAssertEqual(alpha.fileCount, 2)
    }

    // MARK: - Test 7.4: End-to-end scanToDatabase → finalize → VirtualTreeProvider

    func testEndToEndScanToDatabaseThenVirtualTreeProviderReturnsCorrectTree() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let alpha = directory.appendingPathComponent("alpha", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try writeFile(at: alpha.appendingPathComponent("a.txt"), size: 10)
        try writeFile(at: alpha.appendingPathComponent("b.txt"), size: 20)
        try writeFile(at: directory.appendingPathComponent("c.log"), size: 5)

        let db = try FileTreeDatabase()
        let writer = ScanDatabaseWriter(database: db)
        let scanID = UUID()
        try writer.beginScan(scanID: scanID, rootPath: directory.standardizedFileURL.path)

        let scanner = ScannerService()
        let events = await scanner.scanToDatabase(directory: directory, scanID: scanID, databaseWriter: writer)
        _ = await collectEvents(from: events)

        // scanToDatabase calls finalize() internally, which aggregates sizes
        let provider = VirtualTreeProvider(database: db, scanID: scanID)
        let root = try XCTUnwrap(provider.rootNode(maxDepth: 6))

        XCTAssertTrue(root.isDirectory)
        XCTAssertEqual(root.size, 35) // 10 + 20 + 5
        XCTAssertEqual(root.fileCount, 3)

        let rootChildren = root.children ?? []
        XCTAssertEqual(rootChildren.count, 2) // alpha dir + c.log

        let alphaChild = try XCTUnwrap(rootChildren.first(where: { $0.name == "alpha" }))
        XCTAssertTrue(alphaChild.isDirectory)
        XCTAssertEqual(alphaChild.size, 30)
        XCTAssertEqual(alphaChild.fileCount, 2)

        let cLog = try XCTUnwrap(rootChildren.first(where: { $0.name == "c.log" }))
        XCTAssertFalse(cLog.isDirectory)
        XCTAssertEqual(cLog.size, 5)
    }

    // MARK: - Helpers

    private func collectEvents(from stream: AsyncStream<ScanEvent>) async -> [ScanEvent] {
        var events: [ScanEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeFile(at url: URL, size: Int) throws {
        let data = Data(repeating: 65, count: size)
        FileManager.default.createFile(atPath: url.path, contents: data)
    }
}
