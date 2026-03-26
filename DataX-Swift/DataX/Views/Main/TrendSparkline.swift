import Charts
import SwiftUI

enum ScanTrendDirection: Equatable {
    case growth
    case reduction
    case neutral
}

struct TrendSparklinePoint: Identifiable, Equatable {
    let timestamp: Date
    let totalSize: UInt64

    var id: String {
        "\(timestamp.timeIntervalSinceReferenceDate)-\(totalSize)"
    }
}

struct ScanTrendSummary {
    let points: [TrendSparklinePoint]
    let deltaBytes: Int64

    var deltaDirection: ScanTrendDirection {
        switch deltaBytes {
        case let value where value > 0:
            .growth
        case let value where value < 0:
            .reduction
        default:
            .neutral
        }
    }

    var formattedDeltaText: String {
        let sign = switch deltaDirection {
        case .growth:
            "+"
        case .reduction:
            "-"
        case .neutral:
            ""
        }

        let magnitudeText = if deltaBytes == 0 {
            "0 bytes"
        } else {
            SizeFormatter.format(deltaBytes.magnitude)
        }

        return "\(sign)\(magnitudeText) since last scan"
    }

    var accessibilityValue: String {
        guard let latestPoint = points.last else { return formattedDeltaText }
        return "Latest size \(SizeFormatter.format(latestPoint.totalSize)). \(formattedDeltaText)."
    }
}

enum ScanTrendSummaryBuilder {
    private static let maxVisibleRecords = 10

    static func filteredRecentRecords(
        from records: [ScanRecord],
        matchingRootPath rootPath: String
    ) -> [ScanRecord] {
        let newestFirst = records
            .filter { $0.rootPath == rootPath }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }

                return lhs.totalSize > rhs.totalSize
            }

        return Array(newestFirst.prefix(maxVisibleRecords).reversed())
    }

    static func points(from recentRecords: [ScanRecord]) -> [TrendSparklinePoint] {
        recentRecords.map { record in
            TrendSparklinePoint(
                timestamp: record.timestamp,
                totalSize: record.totalSize
            )
        }
    }

    static func deltaBytes(from recentRecords: [ScanRecord]) -> Int64? {
        guard recentRecords.count >= 2 else { return nil }

        let newestTwo = Array(recentRecords.suffix(2))
        let previous = newestTwo[0].totalSize
        let newest = newestTwo[1].totalSize

        if newest >= previous {
            return Int64(min(newest - previous, UInt64(Int64.max)))
        }

        return -Int64(min(previous - newest, UInt64(Int64.max)))
    }

    static func summary(
        from records: [ScanRecord],
        matchingRootPath rootPath: String
    ) -> ScanTrendSummary? {
        let recentRecords = filteredRecentRecords(from: records, matchingRootPath: rootPath)

        guard recentRecords.count >= 2,
              let deltaBytes = deltaBytes(from: recentRecords) else {
            return nil
        }

        return ScanTrendSummary(
            points: points(from: recentRecords),
            deltaBytes: deltaBytes
        )
    }
}

struct TrendSparkline: View {
    let points: [TrendSparklinePoint]

    private var lineColor: Color {
        .secondary.opacity(0.85)
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map { Double($0.totalSize) }
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
        }

        if minimum == maximum {
            let padding = max(maximum * 0.02, 1)
            return (minimum - padding)...(maximum + padding)
        }

        let padding = max((maximum - minimum) * 0.12, 1)
        return (minimum - padding)...(maximum + padding)
    }

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Timestamp", point.timestamp),
                y: .value("Total Size", Double(point.totalSize))
            )
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .foregroundStyle(lineColor)

            if point.id == points.last?.id {
                PointMark(
                    x: .value("Timestamp", point.timestamp),
                    y: .value("Total Size", Double(point.totalSize))
                )
                .symbolSize(10)
                .foregroundStyle(lineColor)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yDomain)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.clear)
        }
        .frame(width: 104, height: 20)
        .allowsHitTesting(false)
        .accessibilityLabel("Scan size trend")
    }
}
