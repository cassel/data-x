import XCTest
@testable import DataX

@MainActor
final class ScannerViewModelDuplicateTests: XCTestCase {
    func testScanForDuplicatesUsesRootTreeCachesResultsAndInvalidatesAfterMoveToTrash() async throws {
        let report = DuplicateReport(groups: [
            DuplicateGroup(
                size: 4_096,
                files: [
                    DuplicateFile(path: "/root/elsewhere/keep.bin", size: 4_096, modificationDate: nil),
                    DuplicateFile(path: "/root/focused/copy.bin", size: 4_096, modificationDate: nil),
                ]
            )
        ], unreadablePaths: [])
        let detector = StubDuplicateDetector(reports: [report, report])
        let viewModel = ScannerViewModel(duplicateDetector: detector)

        let duplicateOutsideCurrent = makeFile("/root/elsewhere/keep.bin", size: 4_096)
        let elsewhere = makeDirectory("/root/elsewhere", children: [duplicateOutsideCurrent])
        let duplicateInsideCurrent = makeFile("/root/focused/copy.bin", size: 4_096)
        let focusedKeep = makeFile("/root/focused/keep.txt", size: 2_048)
        let focused = makeDirectory("/root/focused", children: [duplicateInsideCurrent, focusedKeep])
        let root = makeDirectory("/root", children: [focused, elsewhere])

        viewModel.rootNode = root
        viewModel.currentNode = focused
        viewModel.navigationStack = [root, focused]

        viewModel.scanForDuplicates()

        XCTAssertEqual(viewModel.duplicateReportState, .loading)
        let firstLoadCompleted = await waitForLoadedReport(on: viewModel)
        let firstCallCount = await detector.currentCallCount()
        let firstCandidatePaths = await detector.firstRecordedCandidatePaths()

        XCTAssertTrue(firstLoadCompleted)
        XCTAssertEqual(firstCallCount, 1)
        XCTAssertEqual(
            firstCandidatePaths,
            [
                "/root/elsewhere/keep.bin",
                "/root/focused/copy.bin",
                "/root/focused/keep.txt",
            ]
        )

        viewModel.scanForDuplicates()

        let cachedCallCount = await detector.currentCallCount()
        XCTAssertEqual(cachedCallCount, 1)

        viewModel.commitMoveToTrash(duplicateInsideCurrent)

        XCTAssertEqual(viewModel.duplicateReportState, .idle)

        viewModel.scanForDuplicates()

        let secondLoadCompleted = await waitForLoadedReport(on: viewModel)
        let secondCallCount = await detector.currentCallCount()

        XCTAssertTrue(secondLoadCompleted)
        XCTAssertEqual(secondCallCount, 2)
    }

    func testDeleteFileInvalidatesDuplicateReport() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("file.bin")
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 1, count: 2_048))

        let node = FileNode(url: url, isDirectory: false, size: 2_048, modificationDate: nil)
        let root = makeDirectory("/root", children: [node])
        let viewModel = ScannerViewModel(duplicateDetector: StubDuplicateDetector(reports: []))
        viewModel.rootNode = root
        viewModel.currentNode = root
        viewModel.navigationStack = [root]
        viewModel.duplicateReportState = .loaded(
            DuplicateReport(groups: [
                DuplicateGroup(size: 2_048, files: [
                    DuplicateFile(path: url.standardizedFileURL.path, size: 2_048, modificationDate: nil),
                    DuplicateFile(path: "/root/other.bin", size: 2_048, modificationDate: nil),
                ])
            ], unreadablePaths: [])
        )

        viewModel.deleteFile(node)

        XCTAssertEqual(viewModel.duplicateReportState, .idle)
    }

    func testIsLargeScanForDuplicatesReturnsFalseWhenNoRootNode() {
        let viewModel = ScannerViewModel(duplicateDetector: StubDuplicateDetector(reports: []))
        XCTAssertFalse(viewModel.isLargeScanForDuplicates)
    }

    func testIsLargeScanForDuplicatesReturnsFalseAtThreshold() {
        let viewModel = ScannerViewModel(duplicateDetector: StubDuplicateDetector(reports: []))
        let root = makeDirectory("/root", children: [])
        root.fileCount = 500_000
        viewModel.rootNode = root
        XCTAssertFalse(viewModel.isLargeScanForDuplicates)
    }

    func testIsLargeScanForDuplicatesReturnsTrueAboveThreshold() {
        let viewModel = ScannerViewModel(duplicateDetector: StubDuplicateDetector(reports: []))
        let root = makeDirectory("/root", children: [])
        root.fileCount = 500_001
        viewModel.rootNode = root
        XCTAssertTrue(viewModel.isLargeScanForDuplicates)
    }

    func testCompleteRemoteScanInvalidatesDuplicateReport() {
        let oldRoot = makeDirectory("/root", children: [makeFile("/root/old.bin", size: 2_048)])
        let newRoot = makeDirectory("/new-root", children: [makeFile("/new-root/new.bin", size: 8_192)])
        let viewModel = ScannerViewModel(duplicateDetector: StubDuplicateDetector(reports: []))
        viewModel.rootNode = oldRoot
        viewModel.currentNode = oldRoot
        viewModel.navigationStack = [oldRoot]
        viewModel.duplicateReportState = .loaded(
            DuplicateReport(groups: [
                DuplicateGroup(size: 2_048, files: [
                    DuplicateFile(path: "/root/old.bin", size: 2_048, modificationDate: nil),
                    DuplicateFile(path: "/root/old-copy.bin", size: 2_048, modificationDate: nil),
                ])
            ], unreadablePaths: [])
        )

        viewModel.completeRemoteScan(with: newRoot)

        XCTAssertEqual(viewModel.duplicateReportState, .idle)
        XCTAssertEqual(viewModel.currentNode?.id, newRoot.id)
        XCTAssertEqual(viewModel.navigationStack.map(\.id), [newRoot.id])
    }

    private func waitForLoadedReport(
        on viewModel: ScannerViewModel,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 10_000_000
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if case .loaded = viewModel.duplicateReportState {
                return true
            }

            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }

        if case .loaded = viewModel.duplicateReportState {
            return true
        }

        return false
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeDirectory(_ path: String, children: [FileNode]) -> FileNode {
        let node = FileNode(url: URL(fileURLWithPath: path), isDirectory: true)
        node.children = children
        node.size = children.reduce(0) { $0 + $1.size }
        node.fileCount = children.reduce(0) { $0 + $1.fileCount }
        return node
    }

    private func makeFile(_ path: String, size: UInt64) -> FileNode {
        FileNode(
            url: URL(fileURLWithPath: path),
            isDirectory: false,
            size: size,
            modificationDate: nil
        )
    }
}

private actor StubDuplicateDetector: DuplicateDetecting {
    private(set) var callCount = 0
    private(set) var recordedCandidatePaths: [[String]] = []
    private var reports: [DuplicateReport]

    init(reports: [DuplicateReport]) {
        self.reports = reports
    }

    func detectDuplicates(in candidates: [DuplicateCandidate]) async throws -> DuplicateReport {
        callCount += 1
        recordedCandidatePaths.append(candidates.map { $0.path.standardizedFileURL.path })

        if reports.isEmpty {
            return DuplicateReport(groups: [], unreadablePaths: [])
        }

        return reports[min(callCount - 1, reports.count - 1)]
    }

    func currentCallCount() -> Int {
        callCount
    }

    func firstRecordedCandidatePaths() -> [String]? {
        recordedCandidatePaths.first
    }
}
