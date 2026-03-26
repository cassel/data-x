import AppKit
import Foundation

struct FileOperationsClient {
    var moveToTrash: (URL) throws -> FileOperationsService.TrashResult
    var delete: (URL) throws -> Void
    var restoreFromTrash: (URL, URL) throws -> Void

    static let live = Self(
        moveToTrash: { try FileOperationsService.moveToTrash($0) },
        delete: { try FileOperationsService.delete($0) },
        restoreFromTrash: { try FileOperationsService.restoreFromTrash($0, to: $1) }
    )
}

enum FileOperationsService {
    struct TrashResult: Equatable {
        let originalItemURL: URL
        let trashedItemURL: URL
    }

    enum FileOperationError: LocalizedError {
        case moveToTrashFailed(URL)
        case restoreFailed(URL)
        case restoreDestinationExists(URL)
        case restoreParentMissing(URL)
        case deleteFailed(URL)
        case fileNotFound(URL)
        case permissionDenied(URL)

        var errorDescription: String? {
            switch self {
            case .moveToTrashFailed(let url):
                return "Failed to move '\(url.lastPathComponent)' to Trash"
            case .restoreFailed(let url):
                return "Failed to restore '\(url.lastPathComponent)' from Trash"
            case .restoreDestinationExists(let url):
                return "A file already exists at '\(url.path)'"
            case .restoreParentMissing(let url):
                return "The original parent folder no longer exists for '\(url.lastPathComponent)'"
            case .deleteFailed(let url):
                return "Failed to delete '\(url.lastPathComponent)'"
            case .fileNotFound(let url):
                return "File not found: '\(url.lastPathComponent)'"
            case .permissionDenied(let url):
                return "Permission denied for '\(url.lastPathComponent)'"
            }
        }
    }

    // MARK: - File Operations

    static func moveToTrash(_ url: URL) throws -> TrashResult {
        let standardizedURL = url.standardizedFileURL

        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            throw FileOperationError.fileNotFound(standardizedURL)
        }

        do {
            var trashedItemURL: NSURL?
            try FileManager.default.trashItem(at: standardizedURL, resultingItemURL: &trashedItemURL)

            guard let resultingURL = trashedItemURL as URL? else {
                throw FileOperationError.moveToTrashFailed(standardizedURL)
            }

            return TrashResult(
                originalItemURL: standardizedURL,
                trashedItemURL: resultingURL.standardizedFileURL
            )
        } catch {
            throw mapMoveToTrashError(error, url: standardizedURL)
        }
    }

    static func moveToTrash(_ urls: [URL]) throws -> [TrashResult] {
        try urls.map { try moveToTrash($0) }
    }

    static func delete(_ url: URL) throws {
        let standardizedURL = url.standardizedFileURL

        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            throw FileOperationError.fileNotFound(standardizedURL)
        }

        do {
            try FileManager.default.removeItem(at: standardizedURL)
        } catch {
            throw mapDeleteError(error, url: standardizedURL)
        }
    }

    static func delete(_ urls: [URL]) throws {
        for url in urls {
            try delete(url)
        }
    }

    static func restoreFromTrash(_ trashedURL: URL, to originalURL: URL) throws {
        let standardizedTrashURL = trashedURL.standardizedFileURL
        let standardizedOriginalURL = originalURL.standardizedFileURL
        let parentURL = standardizedOriginalURL.deletingLastPathComponent().standardizedFileURL

        guard FileManager.default.fileExists(atPath: parentURL.path) else {
            throw FileOperationError.restoreParentMissing(standardizedOriginalURL)
        }

        guard !FileManager.default.fileExists(atPath: standardizedOriginalURL.path) else {
            throw FileOperationError.restoreDestinationExists(standardizedOriginalURL)
        }

        do {
            try FileManager.default.moveItem(at: standardizedTrashURL, to: standardizedOriginalURL)
        } catch {
            throw mapRestoreError(error, originalURL: standardizedOriginalURL)
        }
    }

    // MARK: - Reveal & Open

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func openInTerminal(_ url: URL) {
        let dirPath = url.hasDirectoryPath ? url.path : url.deletingLastPathComponent().path

        // Try Terminal.app first
        let script = """
            tell application "Terminal"
                do script "cd '\(dirPath.replacingOccurrences(of: "'", with: "'\\''"))'"
                activate
            end tell
            """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - Quick Look

    static func quickLook(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Copy Path

    static func copyPath(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    // MARK: - Get Info

    static func showGetInfo(_ url: URL) {
        let script = """
            tell application "Finder"
                open information window of (POSIX file "\\(url.path)" as alias)
                activate
            end tell
            """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: - File Info

    static func fileInfo(_ url: URL) -> (size: UInt64, created: Date?, modified: Date?)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        let size = attributes[.size] as? UInt64 ?? 0
        let created = attributes[.creationDate] as? Date
        let modified = attributes[.modificationDate] as? Date

        return (size, created, modified)
    }

    private static func mapMoveToTrashError(_ error: Error, url: URL) -> FileOperationError {
        mapFileOperationError(
            error,
            url: url,
            defaultError: .moveToTrashFailed(url)
        )
    }

    private static func mapDeleteError(_ error: Error, url: URL) -> FileOperationError {
        mapFileOperationError(
            error,
            url: url,
            defaultError: .deleteFailed(url)
        )
    }

    private static func mapRestoreError(_ error: Error, originalURL: URL) -> FileOperationError {
        mapFileOperationError(
            error,
            url: originalURL,
            defaultError: .restoreFailed(originalURL)
        )
    }

    private static func mapFileOperationError(
        _ error: Error,
        url: URL,
        defaultError: FileOperationError
    ) -> FileOperationError {
        if let fileOperationError = error as? FileOperationError {
            return fileOperationError
        }

        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else {
            return defaultError
        }

        let cocoaError = CocoaError.Code(rawValue: nsError.code)

        switch cocoaError {
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return .fileNotFound(url)
        case .fileReadNoPermission, .fileWriteNoPermission:
            return .permissionDenied(url)
        case .fileWriteFileExists:
            return .restoreDestinationExists(url)
        default:
            return defaultError
        }
    }
}
