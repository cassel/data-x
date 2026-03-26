import XCTest
@testable import DataX

final class ScannerServiceTests: XCTestCase {
    func testScanEmptyDirectoryProducesEmptyRootAndCompleteProgress() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let scanner = ScannerService()
        let (stream, continuation) = makeProgressStream()
        let progressTask = Task { await self.collectProgress(from: stream) }

        let result = try await scanner.scan(
            directory: directory,
            progress: continuation
        )
        let progressUpdates = await progressTask.value

        XCTAssertEqual(result.url.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertTrue(result.isDirectory)
        XCTAssertEqual(result.size, 0)
        XCTAssertEqual(result.fileCount, 0)
        XCTAssertTrue((result.children ?? []).isEmpty)
        XCTAssertEqual(progressUpdates.first?.currentPath, directory.lastPathComponent)
        XCTAssertEqual(progressUpdates.first?.isComplete, false)
        XCTAssertEqual(progressUpdates.last?.isComplete, true)
        XCTAssertEqual(progressUpdates.last?.bytesScanned, 0)
    }

    func testScanNestedDirectoryAggregatesSizeAndSkipsHiddenEntriesByDefault() async throws {
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
        let (stream, continuation) = makeProgressStream()
        let progressTask = Task { await self.collectProgress(from: stream) }

        let result = try await scanner.scan(
            directory: directory,
            progress: continuation
        )
        let progressUpdates = await progressTask.value

        XCTAssertEqual(result.size, 35)
        XCTAssertEqual(result.fileCount, 3)
        XCTAssertEqual(result.children?.map { $0.url.lastPathComponent }, ["alpha", "visible.log"])
        XCTAssertEqual(result.children?.first?.size, 30)
        XCTAssertEqual(result.children?.first?.fileCount, 2)
        XCTAssertEqual(progressUpdates.last?.isComplete, true)
        XCTAssertEqual(progressUpdates.last?.filesScanned, 3)
        XCTAssertEqual(progressUpdates.last?.directoriesScanned, 3)
        XCTAssertEqual(progressUpdates.last?.bytesScanned, 35)
    }

    func testScanCancellationStopsWithoutPublishingACompleteProgressEvent() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try makeLargeFixture(at: directory, directoryCount: 24, filesPerDirectory: 160)

        let scanner = ScannerService()
        let (stream, continuation) = makeProgressStream()
        var scanTask: Task<FileNodeData, Error>!

        let progressTask = Task { () -> [ScanProgress] in
            var updates: [ScanProgress] = []
            var requestedCancellation = false

            for await update in stream {
                updates.append(update)

                if !requestedCancellation, update.filesScanned >= 100 {
                    requestedCancellation = true
                    scanTask.cancel()
                    await scanner.cancel()
                }
            }

            return updates
        }

        scanTask = Task {
            try await scanner.scan(
                directory: directory,
                progress: continuation
            )
        }

        do {
            _ = try await scanTask.value
            XCTFail("Expected the scan task to be cancelled")
        } catch is CancellationError {
            // Expected.
        }

        let progressUpdates = await progressTask.value

        XCTAssertTrue(progressUpdates.contains { $0.filesScanned >= 100 })
        XCTAssertFalse(progressUpdates.contains(where: \.isComplete))
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
        XCTAssertEqual(converted.children?.map { $0.name }, ["alpha"])
        XCTAssertEqual(converted.children?.first?.children?.map { $0.name }, ["b.txt", "a.txt"])
        XCTAssertEqual(converted.children?.first?.fileCount, 2)
    }

    private func makeProgressStream() -> (AsyncStream<ScanProgress>, AsyncStream<ScanProgress>.Continuation) {
        var capturedContinuation: AsyncStream<ScanProgress>.Continuation!
        let stream = AsyncStream<ScanProgress>(bufferingPolicy: .unbounded) { continuation in
            capturedContinuation = continuation
        }
        return (stream, capturedContinuation)
    }

    private func collectProgress(from stream: AsyncStream<ScanProgress>) async -> [ScanProgress] {
        var updates: [ScanProgress] = []
        for await update in stream {
            updates.append(update)
        }
        return updates
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
