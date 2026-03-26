import Foundation
import XCTest
@testable import DataX

@MainActor
final class ScanTrendSummaryTests: XCTestCase {
    func testFilteredRecentRecordsMatchExactPathOnly() {
        let targetPath = "/Volumes/Media"
        let records = [
            makeRecord(path: targetPath, timestamp: 100, size: 120),
            makeRecord(path: "\(targetPath)/Projects", timestamp: 200, size: 300),
            makeRecord(path: "/Volumes/Other", timestamp: 300, size: 90),
            makeRecord(path: targetPath, timestamp: 400, size: 240)
        ]

        let recent = ScanTrendSummaryBuilder.filteredRecentRecords(
            from: records,
            matchingRootPath: targetPath
        )

        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.map { $0.rootPath }, [targetPath, targetPath])
        XCTAssertEqual(
            recent.map { $0.timestamp },
            [date(100), date(400)]
        )
    }

    func testFilteredRecentRecordsKeepNewestTenInChronologicalOrder() {
        let targetPath = "/Users/cassel/Projects"
        let records = (0..<12).map { index in
            makeRecord(
                path: targetPath,
                timestamp: TimeInterval(index),
                size: UInt64(index + 1) * 100
            )
        } + [
            makeRecord(path: "/Users/cassel/Desktop", timestamp: 99, size: 9_999)
        ]

        let recent = ScanTrendSummaryBuilder.filteredRecentRecords(
            from: records,
            matchingRootPath: targetPath
        )
        let points = ScanTrendSummaryBuilder.points(from: recent)

        XCTAssertEqual(recent.count, 10)
        XCTAssertEqual(
            recent.map { $0.timestamp },
            (2..<12).map { date(TimeInterval($0)) }
        )
        XCTAssertEqual(
            points.map { $0.timestamp },
            (2..<12).map { date(TimeInterval($0)) }
        )
        XCTAssertEqual(
            points.map { $0.totalSize },
            (3...12).map { UInt64($0) * 100 }
        )
    }

    func testSummaryFormatsGrowthDeltaFromNewestTwoRecords() {
        let targetPath = "/tmp/archive"
        let records = [
            makeRecord(path: targetPath, timestamp: 100, size: 1_024),
            makeRecord(path: targetPath, timestamp: 200, size: 2_048)
        ]

        let summary = ScanTrendSummaryBuilder.summary(
            from: records,
            matchingRootPath: targetPath
        )

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.deltaBytes, 1_024)
        XCTAssertEqual(
            summary?.formattedDeltaText,
            "+\(SizeFormatter.format(UInt64(1_024))) since last scan"
        )
        XCTAssertEqual(summary?.deltaDirection, .growth)
    }

    func testSummaryFormatsReductionDeltaFromNewestTwoRecords() {
        let targetPath = "/tmp/archive"
        let records = [
            makeRecord(path: targetPath, timestamp: 100, size: 2_048),
            makeRecord(path: targetPath, timestamp: 200, size: 512)
        ]

        let summary = ScanTrendSummaryBuilder.summary(
            from: records,
            matchingRootPath: targetPath
        )

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.deltaBytes, -1_536)
        XCTAssertEqual(
            summary?.formattedDeltaText,
            "-\(SizeFormatter.format(UInt64(1_536))) since last scan"
        )
        XCTAssertEqual(summary?.deltaDirection, .reduction)
    }

    func testSummaryFormatsNeutralDeltaFromNewestTwoRecords() {
        let targetPath = "/tmp/archive"
        let records = [
            makeRecord(path: targetPath, timestamp: 100, size: 8_192),
            makeRecord(path: targetPath, timestamp: 200, size: 8_192)
        ]

        let summary = ScanTrendSummaryBuilder.summary(
            from: records,
            matchingRootPath: targetPath
        )

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.deltaBytes, 0)
        XCTAssertEqual(
            summary?.formattedDeltaText,
            "0 bytes since last scan"
        )
        XCTAssertEqual(summary?.deltaDirection, .neutral)
    }

    func testSummaryIsNilWhenFewerThanTwoMatchingRecordsExist() {
        let targetPath = "/tmp/archive"
        let records = [
            makeRecord(path: targetPath, timestamp: 100, size: 1_024),
            makeRecord(path: "\(targetPath)/nested", timestamp: 200, size: 2_048)
        ]

        let summary = ScanTrendSummaryBuilder.summary(
            from: records,
            matchingRootPath: targetPath
        )

        XCTAssertNil(summary)
    }

    private func makeRecord(path: String, timestamp: TimeInterval, size: UInt64) -> ScanRecord {
        ScanRecord(
            rootPath: path,
            timestamp: date(timestamp),
            totalSize: size,
            duration: 1,
            fileCount: 1,
            dirCount: 1,
            topChildrenJSON: "[]"
        )
    }

    private func date(_ timestamp: TimeInterval) -> Date {
        Date(timeIntervalSince1970: timestamp)
    }
}
