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

    func testOldFileClassificationUsesStrictCutoffAndExcludesDirectoriesAndNilDates() throws {
        let calendar = makeCalendar()
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 3,
                day: 26,
                hour: 12
            ))
        )
        let cutoffDate = try XCTUnwrap(
            FilterViewModel.DatePreset.older.cutoffDate(relativeTo: referenceDate, calendar: calendar)
        )
        let olderDate = try XCTUnwrap(calendar.date(byAdding: .second, value: -1, to: cutoffDate))
        let newerDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 30, to: cutoffDate))

        let oldFile = makeFile("/root/archive/old.log", size: 50, modificationDate: olderDate)
        let exactCutoffFile = makeFile("/root/archive/exact.log", size: 40, modificationDate: cutoffDate)
        let recentFile = makeFile("/root/archive/recent.log", size: 30, modificationDate: newerDate)
        let missingDateFile = makeFile("/root/archive/missing.log", size: 20, modificationDate: nil)
        let oldDirectory = makeDirectory(
            "/root/archive",
            children: [],
            modificationDate: olderDate
        )

        XCTAssertTrue(oldFile.isOldFile(cutoffDate: cutoffDate))
        XCTAssertFalse(exactCutoffFile.isOldFile(cutoffDate: cutoffDate))
        XCTAssertFalse(recentFile.isOldFile(cutoffDate: cutoffDate))
        XCTAssertFalse(missingDateFile.isOldFile(cutoffDate: cutoffDate))
        XCTAssertFalse(oldDirectory.isOldFile(cutoffDate: cutoffDate))
    }

    func testOldFileInsightsGroupByDirectoryAndSortDeterministically() throws {
        let calendar = makeCalendar()
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 3,
                day: 26,
                hour: 12
            ))
        )
        let cutoffDate = try XCTUnwrap(
            FilterViewModel.DatePreset.older.cutoffDate(relativeTo: referenceDate, calendar: calendar)
        )
        let oldDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: cutoffDate))
        let recentDate = try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: cutoffDate))

        let alphaLarge = makeFile("/root/alpha/large.bin", size: 400, modificationDate: oldDate)
        let alphaSmall = makeFile("/root/alpha/small.bin", size: 200, modificationDate: oldDate)
        let zetaA = makeFile("/root/zeta/a.bin", size: 300, modificationDate: oldDate)
        let zetaB = makeFile("/root/zeta/b.bin", size: 300, modificationDate: oldDate)
        let recent = makeFile("/root/recent/new.bin", size: 999, modificationDate: recentDate)
        let missing = makeFile("/root/missing/unknown.bin", size: 123, modificationDate: nil)
        let alpha = makeDirectory("/root/alpha", children: [alphaSmall, alphaLarge])
        let zeta = makeDirectory("/root/zeta", children: [zetaB, zetaA])
        let root = makeDirectory("/root", children: [missing, zeta, recent, alpha])

        let insights = ScanInsights.make(from: root, referenceDate: referenceDate, calendar: calendar)
        let oldFiles = try XCTUnwrap(insights.oldFiles)

        XCTAssertEqual(oldFiles.totalCount, 4)
        XCTAssertEqual(oldFiles.totalSize, 1_200)
        XCTAssertEqual(
            oldFiles.directoryGroups.map(\.directoryPath),
            [
                "/root/alpha",
                "/root/zeta",
            ]
        )
        XCTAssertEqual(
            oldFiles.directoryGroups[0].files.map { $0.path.standardizedFileURL.path },
            [
                "/root/alpha/large.bin",
                "/root/alpha/small.bin",
            ]
        )
        XCTAssertEqual(
            oldFiles.directoryGroups[1].files.map { $0.path.standardizedFileURL.path },
            [
                "/root/zeta/a.bin",
                "/root/zeta/b.bin",
            ]
        )
    }

    func testOlderDatePresetRejectsFilesExactlyOnTheCutoff() throws {
        let calendar = makeCalendar()
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 3,
                day: 26,
                hour: 12
            ))
        )
        let cutoffDate = try XCTUnwrap(
            FilterViewModel.DatePreset.older.cutoffDate(relativeTo: referenceDate, calendar: calendar)
        )
        let olderDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: cutoffDate))

        let filter = FilterViewModel()
        filter.datePreset = .older
        filter.maxDate = cutoffDate

        XCTAssertTrue(filter.matches(makeFile("/root/archive/old.log", size: 5, modificationDate: olderDate)))
        XCTAssertFalse(filter.matches(makeFile("/root/archive/exact.log", size: 5, modificationDate: cutoffDate)))
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

    private func makeDirectory(
        _ path: String,
        children: [FileNode] = [],
        modificationDate: Date? = nil
    ) -> FileNode {
        let node = FileNode(
            url: URL(fileURLWithPath: path),
            isDirectory: true,
            modificationDate: modificationDate
        )
        node.children = children
        node.size = children.reduce(0) { $0 + $1.size }
        node.fileCount = children.reduce(0) { $0 + $1.fileCount }
        return node
    }

    private func makeFile(_ path: String, size: UInt64, modificationDate: Date? = nil) -> FileNode {
        FileNode(
            url: URL(fileURLWithPath: path),
            isDirectory: false,
            size: size,
            modificationDate: modificationDate
        )
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
