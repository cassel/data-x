import AppKit
import XCTest
@testable import DataX

@MainActor
final class FinderServicesTests: XCTestCase {
    func testPasteboardFirstDirectoryUsesFirstScannableFolderURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let validDirectory = root.appendingPathComponent("Valid", isDirectory: true)
        let fileURL = root.appendingPathComponent("note.txt")
        let pasteboard = NSPasteboard.withUniqueName()

        try FileManager.default.createDirectory(at: validDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        FileManager.default.createFile(atPath: fileURL.path, contents: Data("hello".utf8))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([
            URL(string: "https://example.com")! as NSURL,
            fileURL as NSURL,
            validDirectory as NSURL
        ]))

        let resolved = FinderServicePayload.firstDirectory(in: pasteboard)

        XCTAssertEqual(resolved?.standardizedFileURL, validDirectory.standardizedFileURL)
    }

    func testServiceProviderRejectsPasteboardsWithoutDirectories() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("not-a-folder", forType: .string)

        var receivedDirectory: URL?
        let provider = FinderServicesProvider { directory in
            receivedDirectory = directory
        }
        var errorMessage: NSString?

        provider.analyzeFolder(pasteboard, userData: nil, error: &errorMessage)

        XCTAssertNil(receivedDirectory)
        XCTAssertEqual(errorMessage as String?, FinderServicesProvider.invalidDirectoryError)
    }

    func testFinderServiceDirectoryDispatchesImmediatelyWhenWindowBridgeExists() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var activationCount = 0
        var openedWindowCount = 0
        let appState = AppState(activateApplication: {
            activationCount += 1
        })

        appState.installMainWindowBridge {
            openedWindowCount += 1
        }
        appState.handleFinderServiceDirectory(directory)

        XCTAssertEqual(openedWindowCount, 1)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(appState.lastScannedURL?.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertNil(appState.pendingFinderServiceDirectory)
        XCTAssertFalse(appState.showFolderPicker)
        appState.scannerViewModel.cancelScan()
    }

    func testFinderServiceDirectoryQueuesUntilWindowBridgeIsInstalled() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var activationCount = 0
        var openedWindowCount = 0
        let appState = AppState(activateApplication: {
            activationCount += 1
        })

        appState.handleFinderServiceDirectory(directory)

        XCTAssertEqual(
            appState.pendingFinderServiceDirectory?.standardizedFileURL,
            directory.standardizedFileURL
        )
        XCTAssertNil(appState.lastScannedURL)
        XCTAssertEqual(openedWindowCount, 0)
        XCTAssertEqual(activationCount, 0)

        appState.installMainWindowBridge {
            openedWindowCount += 1
        }

        XCTAssertNil(appState.pendingFinderServiceDirectory)
        XCTAssertEqual(openedWindowCount, 1)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(appState.lastScannedURL?.standardizedFileURL, directory.standardizedFileURL)
        appState.scannerViewModel.cancelScan()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
