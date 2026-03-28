import XCTest
@testable import DataX

@MainActor
final class ScannerViewModelIncrementalTests: XCTestCase {
    func testLocalDatabaseFirstScanProducesCorrectFinalTree() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try makeLargeFixture(at: directory, directoryCount: 12, filesPerDirectory: 120)
        try writeFile(at: directory.appendingPathComponent("README.md"), size: 5)

        let viewModel = ScannerViewModel()
        viewModel.scan(directory: directory)

        XCTAssertTrue(viewModel.isScanning)
        XCTAssertTrue(viewModel.isIncrementalScanInProgress)
        XCTAssertEqual(viewModel.currentNode?.id, viewModel.rootNode?.id)
        XCTAssertEqual(viewModel.navigationStack.map(\.id), viewModel.rootNode.map { [$0.id] } ?? [])

        let scanCompleted = await waitUntil(timeoutNanoseconds: 15_000_000_000) {
            !viewModel.isScanning && viewModel.rootNode != nil
        }
        XCTAssertTrue(scanCompleted)
        XCTAssertFalse(viewModel.isIncrementalScanInProgress)

        let rootNode = try XCTUnwrap(viewModel.rootNode)
        XCTAssertTrue(rootNode.isDirectory)
        // 12 dirs * 120 files * 1 byte + 1 file * 5 bytes = 1445 total size
        XCTAssertEqual(rootNode.size, 1445)
        XCTAssertEqual(rootNode.fileCount, 1441)
        // 12 directories + README.md = 13 children
        XCTAssertEqual(rootNode.children?.count, 13)

        // Verify VirtualTreeProvider was set
        XCTAssertNotNil(viewModel.virtualTreeProvider)
    }

    func testCancelScanClearsPartialIncrementalState() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try makeLargeFixture(at: directory, directoryCount: 30, filesPerDirectory: 200)

        let viewModel = ScannerViewModel()
        viewModel.scan(directory: directory)

        // Wait briefly to ensure scan has started
        let scanStarted = await waitUntil {
            viewModel.isScanning && viewModel.rootNode != nil
        }
        XCTAssertTrue(scanStarted)

        viewModel.cancelScan()

        let cancelled = await waitUntil {
            !viewModel.isScanning
        }
        XCTAssertTrue(cancelled)
        XCTAssertNil(viewModel.rootNode)
        XCTAssertNil(viewModel.currentNode)
        XCTAssertTrue(viewModel.navigationStack.isEmpty)
        XCTAssertNil(viewModel.progress)
        XCTAssertFalse(viewModel.isIncrementalScanInProgress)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }

        return condition()
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
