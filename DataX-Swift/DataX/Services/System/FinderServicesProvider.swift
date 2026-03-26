import AppKit

enum FinderServicePayload {
    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        guard let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: nil
        ) as? [NSURL] else {
            return []
        }

        return objects.map { $0 as URL }
    }

    static func firstDirectory(in pasteboard: NSPasteboard) -> URL? {
        FolderIntake.firstDirectory(in: fileURLs(in: pasteboard))
    }
}

final class FinderServicesProvider: NSObject {
    static let invalidDirectoryError = "Select a Finder folder to analyze."

    private let handleAcceptedDirectory: @MainActor (URL) -> Void

    init(handleAcceptedDirectory: @escaping @MainActor (URL) -> Void) {
        self.handleAcceptedDirectory = handleAcceptedDirectory
    }

    @objc(analyzeFolder:userData:error:)
    func analyzeFolder(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let directory = FinderServicePayload.firstDirectory(in: pasteboard) else {
            error.pointee = Self.invalidDirectoryError as NSString
            return
        }

        dispatchAcceptedDirectory(directory)
    }

    private func dispatchAcceptedDirectory(_ directory: URL) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                handleAcceptedDirectory(directory)
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                handleAcceptedDirectory(directory)
            }
        }
    }
}
