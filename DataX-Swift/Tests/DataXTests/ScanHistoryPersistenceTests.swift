import Foundation
import SwiftData
import XCTest
@testable import DataX

@MainActor
final class ScanHistoryPersistenceTests: XCTestCase {
    func testCompletedScanPersistsSingleRecordAndUsesFallbackDirectoryCount() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let viewModel = ScannerViewModel()
        let root = makeDirectory("/Volumes/Media", children: [
            makeDirectory("/Volumes/Media/Projects", children: [
                makeFile("/Volumes/Media/Projects/demo.mov", size: 240)
            ]),
            makeFile("/Volumes/Media/readme.txt", size: 12)
        ])
        let progress = ScanProgress(
            filesScanned: root.fileCount,
            directoriesScanned: 0,
            bytesScanned: root.size,
            currentPath: root.path.path,
            startTime: Date(timeIntervalSince1970: 1_000),
            isComplete: true
        )

        viewModel.configurePersistence(modelContext: context)
        viewModel.handleCompletedScan(root, progress: progress)

        let records = try fetchRecords(in: context)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.rootPath, "/Volumes/Media")
        XCTAssertEqual(records.first?.totalSize, root.size)
        XCTAssertEqual(records.first?.fileCount, root.fileCount)
        XCTAssertEqual(records.first?.dirCount, 2)
        XCTAssertEqual(records.first?.topChildrenJSON, try ScanRecord.encodeTopChildren(from: root))
        XCTAssertEqual(viewModel.rootNode?.id, root.id)
        XCTAssertEqual(viewModel.currentNode?.id, root.id)
        XCTAssertEqual(viewModel.navigationStack.map(\.id), [root.id])
        XCTAssertFalse(viewModel.isScanning)
        XCTAssertFalse(viewModel.isIncrementalScanInProgress)
    }

    func testMakeScanRecordSupportsDuplicatePathsAndTimestampOrdering() throws {
        let viewModel = ScannerViewModel()
        let root = makeDirectory("/tmp/archive", children: [
            makeFile("/tmp/archive/a.bin", size: 10),
            makeFile("/tmp/archive/b.bin", size: 20)
        ])
        let olderTimestamp = Date(timeIntervalSince1970: 2_000)
        let newerTimestamp = Date(timeIntervalSince1970: 2_100)
        let progress = ScanProgress(
            filesScanned: root.fileCount,
            directoriesScanned: 1,
            bytesScanned: root.size,
            currentPath: root.path.path,
            startTime: Date(timeIntervalSince1970: 1_900),
            isComplete: true
        )
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)

        let older = try viewModel.makeScanRecord(root: root, progress: progress, timestamp: olderTimestamp)
        let newer = try viewModel.makeScanRecord(root: root, progress: progress, timestamp: newerTimestamp)
        context.insert(older)
        context.insert(newer)
        try context.save()

        let records = try fetchRecords(
            in: context,
            sortBy: [SortDescriptor(\ScanRecord.timestamp, order: .forward)]
        )

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.map(\.rootPath), ["/tmp/archive", "/tmp/archive"])
        XCTAssertEqual(records.map(\.timestamp), [olderTimestamp, newerTimestamp])
        XCTAssertEqual(records.map(\.duration), [100, 200])
    }

    func testPersistedRecordsSurviveStoreReopen() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = storeDirectory.appendingPathComponent("ScanHistory.store")
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        do {
            let container = try makeFileBackedContainer(url: storeURL)
            let context = ModelContext(container)
            let viewModel = ScannerViewModel()
            let root = makeDirectory("/Users/cassel/Documents", children: [
                makeDirectory("/Users/cassel/Documents/Notes", children: [
                    makeFile("/Users/cassel/Documents/Notes/plan.md", size: 4)
                ])
            ])
            let progress = ScanProgress(
                filesScanned: root.fileCount,
                directoriesScanned: 2,
                bytesScanned: root.size,
                currentPath: root.path.path,
                startTime: Date(timeIntervalSince1970: 500),
                isComplete: true
            )

            viewModel.configurePersistence(modelContext: context)
            viewModel.handleCompletedScan(root, progress: progress)
        }

        let reopenedContainer = try makeFileBackedContainer(url: storeURL)
        let reopenedContext = ModelContext(reopenedContainer)
        let records = try fetchRecords(in: reopenedContext)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.rootPath, "/Users/cassel/Documents")
        XCTAssertEqual(records.first?.dirCount, 2)
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ScanRecord.self, configurations: configuration)
    }

    private func makeFileBackedContainer(url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(url: url)
        return try ModelContainer(for: ScanRecord.self, configurations: configuration)
    }

    private func fetchRecords(
        in context: ModelContext,
        sortBy: [SortDescriptor<ScanRecord>] = [SortDescriptor(\ScanRecord.timestamp, order: .reverse)]
    ) throws -> [ScanRecord] {
        let descriptor = FetchDescriptor<ScanRecord>(sortBy: sortBy)
        return try context.fetch(descriptor)
    }

    private func makeDirectory(_ path: String, children: [FileNode]) -> FileNode {
        let node = FileNode(url: URL(fileURLWithPath: path), isDirectory: true)
        node.children = children
        node.size = children.reduce(0) { $0 + $1.size }
        node.fileCount = children.reduce(0) { $0 + $1.fileCount }
        return node
    }

    private func makeFile(_ path: String, size: UInt64) -> FileNode {
        FileNode(url: URL(fileURLWithPath: path), isDirectory: false, size: size)
    }
}
