import XCTest
@testable import DataX

final class WelcomeScreenLogicTests: XCTestCase {
    func testWelcomeRecentsSortByLastUsedThenCreatedAtAndLimitToThree() {
        var oldest = SSHConnection(
            id: "oldest",
            name: "Oldest",
            host: "old.example.com",
            username: "cassel"
        )
        oldest.createdAt = 100
        oldest.lastUsedAt = nil

        var recentlyCreated = SSHConnection(
            id: "recent-created",
            name: "Recent Created",
            host: "created.example.com",
            username: "cassel"
        )
        recentlyCreated.createdAt = 400
        recentlyCreated.lastUsedAt = nil

        var recentlyUsed = SSHConnection(
            id: "recent-used",
            name: "Recent Used",
            host: "used.example.com",
            username: "cassel"
        )
        recentlyUsed.createdAt = 200
        recentlyUsed.lastUsedAt = 900

        var secondRecentlyUsed = SSHConnection(
            id: "second-used",
            name: "Second Used",
            host: "second.example.com",
            username: "cassel"
        )
        secondRecentlyUsed.createdAt = 300
        secondRecentlyUsed.lastUsedAt = 700

        let ordered = SSHViewModel.sortedWelcomeConnections([
            oldest,
            recentlyCreated,
            recentlyUsed,
            secondRecentlyUsed
        ])

        XCTAssertEqual(ordered.map(\.id), [
            "recent-used",
            "second-used",
            "recent-created"
        ])
    }

    func testFirstDirectoryPrefersValidFolderURLsOnly() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let validDirectory = root.appendingPathComponent("Valid", isDirectory: true)
        let fileURL = root.appendingPathComponent("note.txt")

        try FileManager.default.createDirectory(at: validDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(atPath: fileURL.path, contents: Data("hello".utf8))

        let resolved = FolderIntake.firstDirectory(in: [
            URL(string: "https://example.com")!,
            fileURL,
            validDirectory
        ])

        XCTAssertEqual(resolved?.standardizedFileURL, validDirectory.standardizedFileURL)
    }

    func testScannableDirectoryRejectsRegularFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = root.appendingPathComponent("sample.txt")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(atPath: fileURL.path, contents: Data("hello".utf8))

        XCTAssertNil(FolderIntake.scannableDirectory(from: fileURL))
    }
}
