import XCTest
@testable import DataX

final class ToolbarMigrationLogicTests: XCTestCase {
    func testToolbarOptionsExcludeFileTreeAndKeepUserFacingOrder() {
        XCTAssertEqual(
            AppState.VisualizationType.toolbarOptions,
            [.treemap, .sunburst, .icicle, .barChart, .circlePacking]
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
}
