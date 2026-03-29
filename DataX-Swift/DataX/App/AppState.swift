import AppKit
import SwiftUI

enum FolderIntake {
    static func firstDirectory(in urls: [URL]) -> URL? {
        urls.lazy.compactMap(scannableDirectory(from:)).first
    }

    static func scannableDirectory(from url: URL) -> URL? {
        guard url.isFileURL else { return nil }

        let standardizedURL = url.standardizedFileURL
        var isDirectory = ObjCBool(false)

        guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        return standardizedURL
    }
}

@MainActor
@Observable
final class AppState {
    static let mainWindowID = "main"

    var scannerViewModel: ScannerViewModel
    var filterViewModel: FilterViewModel
    var sshViewModel: SSHViewModel
    var showFolderPicker = false
    var showHistoryPanel = false
    var selectedVisualization: VisualizationType = .treemap
    var lastScannedURL: URL?
    var highlightedNode: FileNode?  // Selected in tree, highlighted in treemap (not navigated)
    @ObservationIgnored private var activeSecurityScopedDirectory: URL?
    @ObservationIgnored private let activateApplication: () -> Void
    @ObservationIgnored private var openMainWindowBridge: (() -> Void)?
    @ObservationIgnored private(set) var pendingFinderServiceDirectory: URL?

    init(
        scannerViewModel: ScannerViewModel? = nil,
        filterViewModel: FilterViewModel? = nil,
        sshViewModel: SSHViewModel? = nil,
        activateApplication: (() -> Void)? = nil
    ) {
        self.scannerViewModel = scannerViewModel ?? ScannerViewModel()
        self.filterViewModel = filterViewModel ?? FilterViewModel()
        self.sshViewModel = sshViewModel ?? SSHViewModel()
        self.activateApplication = activateApplication ?? {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var hasScannedContent: Bool {
        scannerViewModel.rootNode != nil
    }

    enum VisualizationType: String, CaseIterable, Identifiable {
        case treemap = "Treemap"
        case sunburst = "Sunburst"

        var id: String { rawValue }

        static var toolbarOptions: [Self] {
            [.treemap, .sunburst]
        }

        var icon: String {
            switch self {
            case .treemap: return "square.grid.2x2"
            case .sunburst: return "sun.max"
            }
        }
    }

    func refresh() {
        guard let url = lastScannedURL else { return }
        scannerViewModel.scan(directory: url)
    }

    func scanNowFromMenuBar(openWindow: OpenWindowAction) {
        openWindow(id: Self.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)

        switch MenuBarScanNowIntent.resolve(lastScannedURL: lastScannedURL) {
        case .rescan(let url):
            showFolderPicker = false
            scan(directory: url)
        case .openFolderPicker:
            showFolderPicker = true
        }
    }

    func selectVisualizationFromCommand(_ visualization: VisualizationType) {
        guard hasScannedContent else { return }
        selectedVisualization = visualization
    }

    func selectInsight(_ node: FileNode) {
        guard let rootNode = scannerViewModel.rootNode,
              !scannerViewModel.isScanning,
              rootNode.containsNode(withID: node.id) else {
            return
        }

        selectedVisualization = .treemap
        scannerViewModel.navigateToRoot()
        highlightedNode = node
    }

    func returnHome() {
        scannerViewModel.resetToHomeState()
        lastScannedURL = nil
        highlightedNode = nil
    }

    @discardableResult
    func handleFolderIntake(_ urls: [URL]) -> Bool {
        guard let directory = FolderIntake.firstDirectory(in: urls) else { return false }

        updateSecurityScopedDirectory(for: directory)
        scan(directory: directory)
        return true
    }

    func handleFolderImport(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result else { return }
        _ = handleFolderIntake(urls)
    }

    func installMainWindowBridge(_ bridge: @escaping () -> Void) {
        openMainWindowBridge = bridge
        flushPendingFinderServiceDirectoryIfNeeded()
    }

    func handleFinderServiceDirectory(_ directory: URL) {
        guard let directory = FolderIntake.scannableDirectory(from: directory) else { return }

        guard openMainWindowBridge != nil else {
            pendingFinderServiceDirectory = directory
            return
        }

        deliverFinderServiceDirectory(directory)
    }

    func scan(directory: URL) {
        lastScannedURL = directory
        scannerViewModel.scan(directory: directory)
    }

    private func flushPendingFinderServiceDirectoryIfNeeded() {
        guard let pendingFinderServiceDirectory else { return }
        deliverFinderServiceDirectory(pendingFinderServiceDirectory)
    }

    private func deliverFinderServiceDirectory(_ directory: URL) {
        let standardizedDirectory = directory.standardizedFileURL

        pendingFinderServiceDirectory = nil
        openMainWindowBridge?()
        activateApplication()
        showFolderPicker = false
        _ = handleFolderIntake([standardizedDirectory])
    }

    private func updateSecurityScopedDirectory(for directory: URL) {
        let standardizedDirectory = directory.standardizedFileURL
        let currentDirectory = activeSecurityScopedDirectory?.standardizedFileURL

        guard currentDirectory != standardizedDirectory else { return }

        activeSecurityScopedDirectory?.stopAccessingSecurityScopedResource()

        if standardizedDirectory.startAccessingSecurityScopedResource() {
            activeSecurityScopedDirectory = standardizedDirectory
            saveBookmark(for: standardizedDirectory)
        } else {
            activeSecurityScopedDirectory = nil
        }
    }

    // MARK: - Security-Scoped Bookmarks (persist folder access across launches)

    private static let bookmarksKey = "savedSecurityScopedBookmarks"

    private func saveBookmark(for url: URL) {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        var bookmarks = loadBookmarkDictionary()
        bookmarks[url.path] = bookmarkData
        UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
    }

    /// Restores previously-granted folder access on app launch.
    func restoreBookmarks() {
        let bookmarks = loadBookmarkDictionary()
        for (_, data) in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            if isStale {
                // Re-save the bookmark with fresh data
                saveBookmark(for: url)
            }
            _ = url.startAccessingSecurityScopedResource()
        }
    }

    private func loadBookmarkDictionary() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
    }
}
