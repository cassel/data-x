import XCTest
@testable import DataX

@MainActor
final class ScannerViewModelIncrementalTests: XCTestCase {
    func testLocalIncrementalScanMergesPartialTreesIntoFinalRootParity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try makeLargeFixture(at: directory, directoryCount: 12, filesPerDirectory: 120)
        try writeFile(at: directory.appendingPathComponent("README.md"), size: 5)

        let expectedFinalRoot = try await finalRootSnapshot(for: directory)

        let viewModel = ScannerViewModel()
        viewModel.scan(directory: directory)

        XCTAssertTrue(viewModel.isScanning)
        XCTAssertTrue(viewModel.isIncrementalScanInProgress)
        XCTAssertEqual(viewModel.currentNode?.id, viewModel.rootNode?.id)
        XCTAssertEqual(viewModel.navigationStack.map(\.id), viewModel.rootNode.map { [$0.id] } ?? [])

        let sawPartialTree = await waitUntil {
            viewModel.isScanning && (viewModel.rootNode?.children?.isEmpty == false)
        }
        XCTAssertTrue(sawPartialTree)

        let scanCompleted = await waitUntil {
            !viewModel.isScanning && viewModel.rootNode != nil
        }
        XCTAssertTrue(scanCompleted)
        XCTAssertFalse(viewModel.isIncrementalScanInProgress)

        let rootNode = try XCTUnwrap(viewModel.rootNode)
        XCTAssertEqual(snapshot(for: rootNode), snapshot(for: expectedFinalRoot))
    }

    func testCancelScanClearsPartialIncrementalState() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try makeLargeFixture(at: directory, directoryCount: 30, filesPerDirectory: 200)

        let viewModel = ScannerViewModel()
        viewModel.scan(directory: directory)

        let sawPartialTree = await waitUntil {
            viewModel.isScanning && (viewModel.rootNode?.children?.isEmpty == false)
        }
        XCTAssertTrue(sawPartialTree)

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

    private func finalRootSnapshot(for directory: URL) async throws -> FileNodeData {
        let scanner = ScannerService()
        let events = await scanner.scan(directory: directory)

        for await event in events {
            if case .complete(let root) = event {
                return root
            }
        }

        XCTFail("Expected a complete scan event")
        throw CancellationError()
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

    private func snapshot(for root: FileNodeData) -> TreeSnapshot {
        TreeSnapshot(
            path: root.url.standardizedFileURL.path,
            size: root.size,
            fileCount: root.fileCount,
            children: (root.children ?? [])
                .map(snapshot(for:))
                .sorted { $0.path < $1.path }
        )
    }

    private func snapshot(for root: FileNode) -> TreeSnapshot {
        TreeSnapshot(
            path: root.path.standardizedFileURL.path,
            size: root.size,
            fileCount: root.fileCount,
            children: (root.children ?? [])
                .map(snapshot(for:))
                .sorted { $0.path < $1.path }
        )
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

private struct TreeSnapshot: Equatable {
    let path: String
    let size: UInt64
    let fileCount: Int
    let children: [TreeSnapshot]
}
