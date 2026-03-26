import XCTest
@testable import DataX

final class ToolbarMigrationLogicTests: XCTestCase {
    @MainActor
    func testAppStateDefaultsToTreemapVisualization() {
        let appState = AppState()

        XCTAssertEqual(appState.selectedVisualization, .treemap)
    }

    func testVisualizationModesAreReducedToTreemapAndSunburst() {
        XCTAssertEqual(
            AppState.VisualizationType.allCases,
            [.treemap, .sunburst]
        )
    }

    func testToolbarOptionsKeepOnlySupportedUserFacingOrder() {
        XCTAssertEqual(
            AppState.VisualizationType.toolbarOptions,
            [.treemap, .sunburst]
        )
    }

    func testSupportedVisualizationLabelsAndIconsRemainStable() {
        XCTAssertEqual(
            AppState.VisualizationType.toolbarOptions.map(\.rawValue),
            ["Treemap", "Sunburst"]
        )
        XCTAssertEqual(
            AppState.VisualizationType.toolbarOptions.map(\.icon),
            ["square.grid.2x2", "sun.max"]
        )
    }

    func testLegendStatsAggregateOnlyTheCurrentNodeSubtreeAndSortBySize() {
        let root = FileNode(url: URL(fileURLWithPath: "/root"), isDirectory: true)
        let focusedDirectory = FileNode(url: URL(fileURLWithPath: "/root/focused"), isDirectory: true)
        let image = FileNode(url: URL(fileURLWithPath: "/root/focused/preview.jpg"), isDirectory: false, size: 300)
        let code = FileNode(url: URL(fileURLWithPath: "/root/focused/main.swift"), isDirectory: false, size: 100)
        let outsideVideo = FileNode(url: URL(fileURLWithPath: "/root/movie.mp4"), isDirectory: false, size: 1_000)

        focusedDirectory.children = [image, code]
        focusedDirectory.fileCount = 2
        root.children = [focusedDirectory, outsideVideo]
        root.fileCount = 3

        let stats = FileTypeLegendStats.make(for: focusedDirectory)

        XCTAssertEqual(stats.map(\.category), [.images, .code])
        XCTAssertEqual(stats.map(\.size), [300, 100])
        XCTAssertEqual(stats.map(\.count), [1, 1])
    }

    func testInsightRankingsSortBySizeThenPathAndExcludeRootDirectory() {
        let alpha = makeFile("/root/alpha.log", size: 400)
        let zeta = makeFile("/root/zeta.log", size: 400)
        let docsLarge = makeFile("/root/docs/manual.pdf", size: 500)
        let appsLarge = makeFile("/root/apps/tool.app", size: 500)
        let docs = makeDirectory("/root/docs", children: [docsLarge])
        let apps = makeDirectory("/root/apps", children: [appsLarge])
        let root = makeDirectory("/root", children: [zeta, docs, alpha, apps])

        let insights = ScanInsights.make(from: root)

        XCTAssertEqual(
            insights.topFiles.map { $0.path.standardizedFileURL.path },
            [
                "/root/apps/tool.app",
                "/root/docs/manual.pdf",
                "/root/alpha.log",
                "/root/zeta.log",
            ]
        )
        XCTAssertEqual(
            insights.topDirectories.map { $0.path.standardizedFileURL.path },
            [
                "/root/apps",
                "/root/docs",
            ]
        )
    }

    func testInsightRankingsHandleShortScansWithoutPadding() {
        let loneFile = makeFile("/root/only.dat", size: 42)
        let root = makeDirectory("/root", children: [loneFile])

        let insights = ScanInsights.make(from: root)

        XCTAssertEqual(insights.topFiles.map(\.id), [loneFile.id])
        XCTAssertTrue(insights.topDirectories.isEmpty)
    }

    @MainActor
    func testInsightSelectionSwitchesToTreemapReturnsToRootAndHighlightsNode() {
        let appState = AppState()
        let selectedNode = makeFile("/root/archive/movie.mov", size: 700)
        let archive = makeDirectory("/root/archive", children: [selectedNode])
        let focusedFile = makeFile("/root/focused/note.txt", size: 10)
        let focused = makeDirectory("/root/focused", children: [focusedFile])
        let root = makeDirectory("/root", children: [focused, archive])

        appState.scannerViewModel.rootNode = root
        appState.scannerViewModel.currentNode = focused
        appState.scannerViewModel.navigationStack = [root, focused]
        appState.selectedVisualization = .sunburst

        appState.selectInsight(selectedNode)

        XCTAssertEqual(appState.selectedVisualization, .treemap)
        XCTAssertEqual(appState.scannerViewModel.currentNode?.id, root.id)
        XCTAssertEqual(appState.scannerViewModel.navigationStack.map(\.id), [root.id])
        XCTAssertEqual(appState.highlightedNode?.id, selectedNode.id)
    }

    private func makeDirectory(_ path: String, children: [FileNode] = []) -> FileNode {
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
