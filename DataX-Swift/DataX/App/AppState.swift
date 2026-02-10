import SwiftUI

@Observable
final class AppState {
    var scannerViewModel = ScannerViewModel()
    var filterViewModel = FilterViewModel()
    var sshViewModel = SSHViewModel()
    var showFolderPicker = false
    var selectedVisualization: VisualizationType = .treemap
    var lastScannedURL: URL?
    var highlightedNode: FileNode?  // Selected in tree, highlighted in treemap (not navigated)

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

    func scan(directory: URL) {
        lastScannedURL = directory
        scannerViewModel.scan(directory: directory)
    }
}
