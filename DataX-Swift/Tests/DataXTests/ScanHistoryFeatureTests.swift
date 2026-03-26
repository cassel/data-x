import Foundation
import XCTest
@testable import DataX

@MainActor
final class ScanHistoryFeatureTests: XCTestCase {
    func testGroupedHistoryRowsGroupByExactPathAndOrderGroupsByNewestScan() {
        let records = [
            makeRecord(path: "/Volumes/Archive", timestamp: 150, size: 300),
            makeRecord(path: "/Users/cassel/Documents", timestamp: 100, size: 100),
            makeRecord(path: "/Users/cassel/Documents", timestamp: 200, size: 140),
            makeRecord(path: "/Users/cassel/Documents/Notes", timestamp: 250, size: 90)
        ]

        let groups = ScanHistoryBrowserModel.groupedHistoryRows(from: records)

        XCTAssertEqual(groups.map(\.rootPath), [
            "/Users/cassel/Documents/Notes",
            "/Users/cassel/Documents",
            "/Volumes/Archive"
        ])
        XCTAssertEqual(groups[1].rows.map(\.timestamp), [date(200), date(100)])
    }

    func testGroupedHistoryRowsComputeDeltaAgainstPreviousRecordInSamePath() throws {
        let records = [
            makeRecord(path: "/tmp/archive", timestamp: 100, size: 100),
            makeRecord(path: "/tmp/archive", timestamp: 200, size: 160),
            makeRecord(path: "/tmp/archive", timestamp: 300, size: 120),
            makeRecord(path: "/tmp/other", timestamp: 400, size: 999)
        ]

        let groups = ScanHistoryBrowserModel.groupedHistoryRows(from: records)
        let archiveRows = try XCTUnwrap(groups.first(where: { $0.rootPath == "/tmp/archive" })?.rows)

        XCTAssertEqual(archiveRows.map(\.timestamp), [date(300), date(200), date(100)])
        XCTAssertEqual(archiveRows.map(\.deltaBytes), [-40, 60, nil])
        XCTAssertEqual(archiveRows.map(\.formattedDeltaText), ["-40 bytes", "+60 bytes", "No previous scan"])
    }

    func testGrowthAlertTriggersForAbsoluteThreshold() {
        let recentRecords = [
            makeRecord(path: "/Volumes/Media", timestamp: 200, size: 11_100_000_000),
            makeRecord(path: "/Volumes/Media", timestamp: 100, size: 5_000_000_000)
        ]

        let alert = ScanGrowthAlertEvaluator.growthAlertState(from: recentRecords)

        XCTAssertEqual(alert?.path, "/Volumes/Media")
        XCTAssertEqual(alert?.growthBytes, 6_100_000_000)
        XCTAssertEqual(alert?.previousScanDate, date(100))
    }

    func testGrowthAlertTriggersForPercentageThreshold() {
        let recentRecords = [
            makeRecord(path: "/Users/cassel/Projects", timestamp: 200, size: 1_300),
            makeRecord(path: "/Users/cassel/Projects", timestamp: 100, size: 1_000)
        ]

        let alert = ScanGrowthAlertEvaluator.growthAlertState(from: recentRecords)

        XCTAssertEqual(alert?.growthBytes, 300)
        XCTAssertEqual(alert?.formattedGrowthText, "300 bytes")
    }

    func testGrowthAlertDoesNotTriggerForFlatOrReducedScans() {
        let flatRecords = [
            makeRecord(path: "/tmp/archive", timestamp: 200, size: 1_000),
            makeRecord(path: "/tmp/archive", timestamp: 100, size: 1_000)
        ]
        let reducedRecords = [
            makeRecord(path: "/tmp/archive", timestamp: 200, size: 900),
            makeRecord(path: "/tmp/archive", timestamp: 100, size: 1_000)
        ]

        XCTAssertNil(ScanGrowthAlertEvaluator.growthAlertState(from: flatRecords))
        XCTAssertNil(ScanGrowthAlertEvaluator.growthAlertState(from: reducedRecords))
    }

    func testGrowthAlertUsesAbsoluteRuleWhenPreviousSizeIsZero() {
        let smallGrowth = [
            makeRecord(path: "/tmp/archive", timestamp: 200, size: 4_000_000_000),
            makeRecord(path: "/tmp/archive", timestamp: 100, size: 0)
        ]
        let largeGrowth = [
            makeRecord(path: "/tmp/archive", timestamp: 200, size: 6_000_000_000),
            makeRecord(path: "/tmp/archive", timestamp: 100, size: 0)
        ]

        XCTAssertNil(ScanGrowthAlertEvaluator.growthAlertState(from: smallGrowth))
        XCTAssertNotNil(ScanGrowthAlertEvaluator.growthAlertState(from: largeGrowth))
    }

    func testGrowthAlertReturnsNilWhenPreviousRecordIsMissing() {
        let recentRecords = [
            makeRecord(path: "/tmp/archive", timestamp: 200, size: 6_000_000_000)
        ]

        XCTAssertNil(ScanGrowthAlertEvaluator.growthAlertState(from: recentRecords))
    }

    func testHistoryPreviewSnapshotsDecodeSelectedRecordTopChildren() throws {
        let record = ScanRecord(
            rootPath: "/tmp/archive",
            timestamp: date(100),
            totalSize: 3_000,
            duration: 12,
            fileCount: 2,
            dirCount: 1,
            topChildrenJSON: """
            [
              {"isDirectory": true, "name": "Projects", "size": 2000},
              {"isDirectory": false, "name": "notes.txt", "size": 1000}
            ]
            """
        )

        let snapshots = try ScanHistoryBrowserModel.historyPreviewSnapshots(from: record)

        XCTAssertEqual(
            snapshots,
            [
                HistoryPreviewSnapshot(name: "Projects", size: 2_000, isDirectory: true),
                HistoryPreviewSnapshot(name: "notes.txt", size: 1_000, isDirectory: false)
            ]
        )
    }

    private func makeRecord(path: String, timestamp: TimeInterval, size: UInt64) -> ScanRecord {
        ScanRecord(
            rootPath: path,
            timestamp: date(timestamp),
            totalSize: size,
            duration: 5,
            fileCount: 3,
            dirCount: 2,
            topChildrenJSON: "[]"
        )
    }

    private func date(_ timestamp: TimeInterval) -> Date {
        Date(timeIntervalSince1970: timestamp)
    }
}
