import SwiftData
import XCTest
@testable import DataX

@MainActor
final class ScanRecordTests: XCTestCase {
    func testModelContainerBootstrapsInMemory() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

        XCTAssertNoThrow(try ModelContainer(for: ScanRecord.self, configurations: configuration))
    }

    func testSnapshotsPreserveImmediateChildOrderAndFields() {
        let folder = makeDirectory("/root/folder", children: [
            makeFile("/root/folder/deep.bin", size: 200)
        ])
        let file = makeFile("/root/file.bin", size: 100)
        let root = makeDirectory("/root", children: [folder, file])

        XCTAssertEqual(
            ScanRecord.snapshots(from: root),
            [
                ScanRecord.TopChildSnapshot(name: "folder", size: 200, isDirectory: true),
                ScanRecord.TopChildSnapshot(name: "file.bin", size: 100, isDirectory: false)
            ]
        )
    }

    func testEncodeTopChildrenProducesDeterministicRoundTripJSON() throws {
        let directory = makeDirectory("/root/library", children: [
            makeFile("/root/library/song.aiff", size: 400)
        ])
        let archive = makeFile("/root/archive.zip", size: 150)
        let root = makeDirectory("/root", children: [directory, archive])

        let json = try ScanRecord.encodeTopChildren(from: root)

        XCTAssertEqual(
            json,
            #"[{"isDirectory":true,"name":"library","size":400},{"isDirectory":false,"name":"archive.zip","size":150}]"#
        )

        let record = ScanRecord(
            rootPath: root.path.path,
            timestamp: Date(timeIntervalSince1970: 1_234),
            totalSize: root.size,
            duration: 2.5,
            fileCount: root.fileCount,
            dirCount: 1,
            topChildrenJSON: json
        )

        XCTAssertEqual(
            try record.decodedTopChildren(),
            [
                ScanRecord.TopChildSnapshot(name: "library", size: 400, isDirectory: true),
                ScanRecord.TopChildSnapshot(name: "archive.zip", size: 150, isDirectory: false)
            ]
        )
    }

    func testEncodeTopChildrenOmitsNestedDescendants() throws {
        let nested = makeDirectory("/root/projects/app/Sources", children: [
            makeFile("/root/projects/app/Sources/main.swift", size: 75)
        ])
        let project = makeDirectory("/root/projects/app", children: [nested])
        let root = makeDirectory("/root/projects", children: [project])

        let json = try ScanRecord.encodeTopChildren(from: root)

        XCTAssertTrue(json.contains("app"))
        XCTAssertFalse(json.contains("Sources"))
        XCTAssertFalse(json.contains("main.swift"))
        XCTAssertEqual(
            try ScanRecord(
                rootPath: root.path.path,
                timestamp: Date(),
                totalSize: root.size,
                duration: 1,
                fileCount: root.fileCount,
                dirCount: 2,
                topChildrenJSON: json
            ).decodedTopChildren(),
            [
                ScanRecord.TopChildSnapshot(name: "app", size: 75, isDirectory: true)
            ]
        )
    }

    func testEncodeTopChildrenHandlesRootsWithoutChildren() throws {
        let root = makeDirectory("/root", children: [])

        let json = try ScanRecord.encodeTopChildren(from: root)

        XCTAssertEqual(json, "[]")
        XCTAssertEqual(
            try ScanRecord(
                rootPath: root.path.path,
                timestamp: Date(),
                totalSize: root.size,
                duration: 0.25,
                fileCount: root.fileCount,
                dirCount: 0,
                topChildrenJSON: json
            ).decodedTopChildren(),
            []
        )
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
