import XCTest
@testable import DataX

final class ScannerServiceTests: XCTestCase {
    func testScanEmitsPartialTreeForEachCompletedImmediateChildAndFinalSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let alpha = directory.appendingPathComponent("alpha", isDirectory: true)
        let nested = alpha.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeFile(at: alpha.appendingPathComponent("a.txt"), size: 10)
        try writeFile(at: nested.appendingPathComponent("b.bin"), size: 20)
        try writeFile(at: directory.appendingPathComponent("visible.log"), size: 5)
        try writeFile(at: directory.appendingPathComponent(".hidden"), size: 100)

        let scanner = ScannerService()
        let events = await scanner.scan(directory: directory)
        let collectedEvents = await collectEvents(from: events)

        let partialTrees = collectedEvents.compactMap(\.partialTree)
        let completedRoot = try XCTUnwrap(collectedEvents.compactMap(\.completeTree).last)

        XCTAssertEqual(
            partialTrees.map { $0.url.lastPathComponent }.sorted(),
            ["alpha", "visible.log"]
        )
        XCTAssertEqual(Set(partialTrees.map(\.url.standardizedFileURL)), Set([
            alpha.standardizedFileURL,
            directory.appendingPathComponent("visible.log").standardizedFileURL
        ]))
        XCTAssertEqual(completedRoot.size, 35)
        XCTAssertEqual(completedRoot.fileCount, 3)
        XCTAssertEqual(
            completedRoot.children?.map(\.url.lastPathComponent),
            ["alpha", "visible.log"]
        )

        let progressEvents = collectedEvents.compactMap(\.progressUpdate)
        XCTAssertEqual(progressEvents.first?.currentPath, directory.lastPathComponent)
        XCTAssertEqual(progressEvents.last?.isComplete, true)
    }

    func testScanCancellationFinishesEventStreamWithoutCompleteEvent() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try makeLargeFixture(at: directory, directoryCount: 24, filesPerDirectory: 160)

        let scanner = ScannerService()
        let events = await scanner.scan(directory: directory)
        var collectedEvents: [ScanEvent] = []
        var requestedCancellation = false

        for await event in events {
            collectedEvents.append(event)

            if case .progress(let progress) = event,
               !requestedCancellation,
               progress.filesScanned >= 100 {
                requestedCancellation = true
                await scanner.cancel()
            }
        }

        XCTAssertTrue(collectedEvents.contains { $0.progressUpdate?.filesScanned ?? 0 >= 100 })
        XCTAssertFalse(collectedEvents.contains { $0.completeTree != nil })
    }

    @MainActor
    func testFileNodeDataToFileNodePreservesAggregatesAndChildren() {
        let leafA = FileNodeData(
            url: URL(fileURLWithPath: "/root/alpha/a.txt"),
            isDirectory: false,
            isSymlink: false,
            size: 10,
            modificationDate: nil,
            fileCount: 1,
            children: nil
        )
        let leafB = FileNodeData(
            url: URL(fileURLWithPath: "/root/alpha/b.txt"),
            isDirectory: false,
            isSymlink: false,
            size: 20,
            modificationDate: nil,
            fileCount: 1,
            children: nil
        )
        let folder = FileNodeData(
            url: URL(fileURLWithPath: "/root/alpha"),
            isDirectory: true,
            isSymlink: false,
            size: 30,
            modificationDate: nil,
            fileCount: 2,
            children: [leafB, leafA]
        )
        let root = FileNodeData(
            url: URL(fileURLWithPath: "/root"),
            isDirectory: true,
            isSymlink: false,
            size: 30,
            modificationDate: nil,
            fileCount: 2,
            children: [folder]
        )

        let converted = root.toFileNode()

        XCTAssertEqual(converted.size, 30)
        XCTAssertEqual(converted.fileCount, 2)
        XCTAssertEqual(converted.children?.map(\.name), ["alpha"])
        XCTAssertEqual(converted.children?.first?.children?.map(\.name), ["b.txt", "a.txt"])
        XCTAssertEqual(converted.children?.first?.fileCount, 2)
    }

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

    private func makeLargeFixture(at root: URL, directoryCount: Int, filesPerDirectory: Int) throws {
        for directoryIndex in 0..<directoryCount {
            let directory = root.appendingPathComponent("dir-\(directoryIndex)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            for fileIndex in 0..<filesPerDirectory {
                let fileURL = directory.appendingPathComponent("file-\(fileIndex).dat")
                try writeFile(at: fileURL, size: 1)
            }
        }
    }

    private func writeFile(at url: URL, size: Int) throws {
        let data = Data(repeating: 65, count: size)
        FileManager.default.createFile(atPath: url.path, contents: data)
    }
}

private extension ScanEvent {
    var progressUpdate: ScanProgress? {
        guard case .progress(let progress) = self else { return nil }
        return progress
    }

    var partialTree: FileNodeData? {
        guard case .partialTree(let tree) = self else { return nil }
        return tree
    }

    var completeTree: FileNodeData? {
        guard case .complete(let tree) = self else { return nil }
        return tree
    }
}
