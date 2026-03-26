import XCTest
@testable import DataX

final class DuplicateDetectorTests: XCTestCase {
    @MainActor
    func testDuplicateCandidatesSkipSymlinksSmallFilesAndSortBySizeThenPath() {
        let alpha = makeFile("/root/alpha.bin", size: 8_192)
        let beta = makeFile("/root/beta.bin", size: 8_192)
        let tiny = makeFile("/root/tiny.txt", size: 512)
        let symlink = FileNode(
            url: URL(fileURLWithPath: "/root/link.bin"),
            isDirectory: false,
            isSymlink: true,
            size: 9_000,
            modificationDate: nil
        )
        let nested = makeDirectory("/root/nested", children: [
            makeFile("/root/nested/movie.mov", size: 16_384)
        ])
        let root = makeDirectory("/root", children: [beta, symlink, nested, alpha, tiny])

        let candidates = DuplicateCandidate.makeList(from: root)

        XCTAssertEqual(
            candidates.map { $0.path.standardizedFileURL.path },
            [
                "/root/nested/movie.mov",
                "/root/alpha.bin",
                "/root/beta.bin",
            ]
        )
        XCTAssertTrue(candidates.allSatisfy { !$0.isSymlink })
        XCTAssertTrue(candidates.allSatisfy { $0.size >= DuplicateDetector.minimumFileSize })
    }

    func testDetectorDiscardsSameSizeSingletonsAndEliminatesPartialHashMismatches() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let singleton = directory.appendingPathComponent("singleton.bin")
        try writeFile(at: singleton, data: Data(repeating: 1, count: 12_288))

        let left = directory.appendingPathComponent("left.bin")
        let right = directory.appendingPathComponent("right.bin")
        try writeFile(at: left, data: makeData(prefix: 2, middle: 3, suffix: 4, totalSize: 16_384))
        try writeFile(at: right, data: makeData(prefix: 9, middle: 3, suffix: 4, totalSize: 16_384))

        let detector = DuplicateDetector()
        let report = try await detector.detectDuplicates(in: [
            makeCandidate(singleton),
            makeCandidate(left),
            makeCandidate(right),
        ])

        XCTAssertTrue(report.groups.isEmpty)
        XCTAssertTrue(report.unreadablePaths.isEmpty)
    }

    func testDetectorRequiresFullHashConfirmationAfterPartialHashCollision() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.bin")
        let second = directory.appendingPathComponent("second.bin")
        try writeFile(at: first, data: makeData(prefix: 7, middle: 3, suffix: 11, totalSize: 10_240))
        try writeFile(at: second, data: makeData(prefix: 7, middle: 99, suffix: 11, totalSize: 10_240))

        let detector = DuplicateDetector()
        let report = try await detector.detectDuplicates(in: [
            makeCandidate(first),
            makeCandidate(second),
        ])

        XCTAssertTrue(report.groups.isEmpty)
    }

    func testPartialDigestUsesWholeFileForFilesUpToEightKilobytes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("small.bin")
        let data = makeSequentialData(count: 6_000)
        try writeFile(at: url, data: data)

        let partialDigest = try DuplicateHasher.partialDigest(
            for: url,
            expectedSize: UInt64(data.count)
        )
        let fullDigest = try DuplicateHasher.fullDigest(
            for: url,
            expectedSize: UInt64(data.count)
        )

        XCTAssertEqual(partialDigest, fullDigest)
    }

    func testUnreadableFilesAreDroppedWithoutAbortingRemainingResults() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let readableA = directory.appendingPathComponent("readable-a.bin")
        let readableB = directory.appendingPathComponent("readable-b.bin")
        let deleted = directory.appendingPathComponent("deleted.bin")
        let sameContent = makeSequentialData(count: 9_216)

        try writeFile(at: readableA, data: sameContent)
        try writeFile(at: readableB, data: sameContent)
        try writeFile(at: deleted, data: sameContent)
        try FileManager.default.removeItem(at: deleted)

        let detector = DuplicateDetector()
        let report = try await detector.detectDuplicates(in: [
            makeCandidate(readableA, size: UInt64(sameContent.count)),
            makeCandidate(readableB, size: UInt64(sameContent.count)),
            DuplicateCandidate(
                path: deleted,
                size: UInt64(sameContent.count),
                modificationDate: nil,
                isSymlink: false
            ),
        ])

        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(
            report.groups[0].files.map(\.path),
            [
                readableA.standardizedFileURL.path,
                readableB.standardizedFileURL.path,
            ]
        )
        XCTAssertEqual(report.unreadablePaths, [deleted.standardizedFileURL.path])
        XCTAssertNotNil(report.warningMessage)
    }

    func testReportOrderingIsDeterministicAndSuggestedOriginalFallsBackToPathWhenDatesTieOrAreMissing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let alphaKeep = directory.appendingPathComponent("group-a/alpha-keep.bin")
        let alphaCopyA = directory.appendingPathComponent("group-a/alpha-copy-a.bin")
        let alphaCopyB = directory.appendingPathComponent("group-a/alpha-copy-b.bin")
        let betaKeep = directory.appendingPathComponent("group-b/beta-keep.bin")
        let betaCopy = directory.appendingPathComponent("group-b/beta-copy.bin")

        let alphaData = makeSequentialData(count: 2_048)
        let betaData = makeSequentialData(count: 4_096)
        let olderDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)

        try writeFile(at: alphaKeep, data: alphaData)
        try writeFile(at: alphaCopyA, data: alphaData)
        try writeFile(at: alphaCopyB, data: alphaData)
        try writeFile(at: betaKeep, data: betaData, modificationDate: olderDate)
        try writeFile(at: betaCopy, data: betaData, modificationDate: newerDate)

        let detector = DuplicateDetector()
        let report = try await detector.detectDuplicates(in: [
            makeCandidate(betaCopy, modificationDate: newerDate),
            makeCandidate(alphaCopyB),
            makeCandidate(alphaKeep),
            makeCandidate(betaKeep, modificationDate: olderDate),
            makeCandidate(alphaCopyA),
        ])

        XCTAssertEqual(report.groups.count, 2)

        XCTAssertEqual(
            report.groups.map(\.canonicalPath),
            [
                alphaCopyA.standardizedFileURL.path,
                betaKeep.standardizedFileURL.path,
            ]
        )
        XCTAssertEqual(
            report.groups[0].files.map(\.path),
            [
                alphaCopyA.standardizedFileURL.path,
                alphaCopyB.standardizedFileURL.path,
                alphaKeep.standardizedFileURL.path,
            ]
        )
        XCTAssertEqual(
            report.groups[1].files.map(\.path),
            [
                betaKeep.standardizedFileURL.path,
                betaCopy.standardizedFileURL.path,
            ]
        )
        XCTAssertEqual(report.groups[0].reclaimableSpace, 4_096)
        XCTAssertEqual(report.groups[1].reclaimableSpace, 4_096)
    }

    @MainActor
    private func makeDirectory(_ path: String, children: [FileNode]) -> FileNode {
        let node = FileNode(url: URL(fileURLWithPath: path), isDirectory: true)
        node.children = children
        node.size = children.reduce(0) { $0 + $1.size }
        node.fileCount = children.reduce(0) { $0 + $1.fileCount }
        return node
    }

    @MainActor
    private func makeFile(_ path: String, size: UInt64) -> FileNode {
        FileNode(
            url: URL(fileURLWithPath: path),
            isDirectory: false,
            size: size,
            modificationDate: nil
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeFile(at url: URL, data: Data, modificationDate: Date? = nil) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: data)

        if let modificationDate {
            try FileManager.default.setAttributes(
                [.modificationDate: modificationDate],
                ofItemAtPath: url.path
            )
        }
    }

    private func makeCandidate(
        _ url: URL,
        size: UInt64? = nil,
        modificationDate: Date? = nil
    ) -> DuplicateCandidate {
        DuplicateCandidate(
            path: url,
            size: size ?? currentSize(of: url),
            modificationDate: modificationDate,
            isSymlink: false
        )
    }

    private func currentSize(of url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? UInt64 ?? 0
    }

    private func makeSequentialData(count: Int) -> Data {
        Data((0..<count).map { UInt8($0 % 251) })
    }

    private func makeData(prefix: UInt8, middle: UInt8, suffix: UInt8, totalSize: Int) -> Data {
        let edgeSize = DuplicateHasher.edgeWindowSize
        let middleCount = max(totalSize - (edgeSize * 2), 0)
        return Data(repeating: prefix, count: edgeSize)
            + Data(repeating: middle, count: middleCount)
            + Data(repeating: suffix, count: edgeSize)
    }
}
