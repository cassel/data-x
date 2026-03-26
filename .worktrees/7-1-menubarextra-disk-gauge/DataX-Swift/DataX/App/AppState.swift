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

@Observable
final class AppState {
    var scannerViewModel = ScannerViewModel()
    var filterViewModel = FilterViewModel()
    var sshViewModel = SSHViewModel()
    var showFolderPicker = false
    var selectedVisualization: VisualizationType = .treemap
    var lastScannedURL: URL?
    var highlightedNode: FileNode?  // Selected in tree, highlighted in treemap (not navigated)
    @ObservationIgnored private var activeSecurityScopedDirectory: URL?

    enum VisualizationType: String, CaseIterable, Identifiable {
        case treemap = "Treemap"
        case sunburst = "Sunburst"
        case icicle = "Icicle"
        case barChart = "Bar Chart"
        case circlePacking = "Circle Packing"
        case fileTree = "File Tree"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .treemap: return "square.grid.2x2"
            case .sunburst: return "sun.max"
            case .icicle: return "chart.bar.xaxis"
            case .barChart: return "chart.bar"
            case .circlePacking: return "circle.hexagongrid"
            case .fileTree: return "list.bullet.indent"
            }
        }
    }

    func refresh() {
        guard let url = lastScannedURL else { return }
        scannerViewModel.scan(directory: url)
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

    func scan(directory: URL) {
        lastScannedURL = directory
        scannerViewModel.scan(directory: directory)
    }

    private func updateSecurityScopedDirectory(for directory: URL) {
        let standardizedDirectory = directory.standardizedFileURL
        let currentDirectory = activeSecurityScopedDirectory?.standardizedFileURL

        guard currentDirectory != standardizedDirectory else { return }

        activeSecurityScopedDirectory?.stopAccessingSecurityScopedResource()

        if standardizedDirectory.startAccessingSecurityScopedResource() {
            activeSecurityScopedDirectory = standardizedDirectory
        } else {
            activeSecurityScopedDirectory = nil
        }
    }
}
