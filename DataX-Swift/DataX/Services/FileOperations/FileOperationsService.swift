import AppKit
import Foundation

enum FileOperationsService {
    enum FileOperationError: LocalizedError {
        case moveToTrashFailed(URL)
        case deleteFailed(URL)
        case fileNotFound(URL)
        case permissionDenied(URL)

        var errorDescription: String? {
            switch self {
            case .moveToTrashFailed(let url):
                return "Failed to move '\(url.lastPathComponent)' to Trash"
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

    static func moveToTrash(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileOperationError.fileNotFound(url)
        }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw FileOperationError.moveToTrashFailed(url)
        }
    }

    static func moveToTrash(_ urls: [URL]) throws {
        for url in urls {
            try moveToTrash(url)
        }
    }

    static func delete(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileOperationError.fileNotFound(url)
        }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw FileOperationError.deleteFailed(url)
        }
    }

    static func delete(_ urls: [URL]) throws {
        for url in urls {
            try delete(url)
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
}
