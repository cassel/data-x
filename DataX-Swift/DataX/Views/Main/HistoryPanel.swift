import SwiftData
import SwiftUI

struct HistoryPreviewSnapshot: Identifiable, Equatable {
    let name: String
    let size: UInt64
    let isDirectory: Bool

    var id: String {
        "\(isDirectory)-\(name)-\(size)"
    }

    var formattedSize: String {
        SizeFormatter.format(size)
    }
}

struct HistoryScanRow: Identifiable, Equatable {
    struct Key: Hashable {
        let rootPath: String
        let timestamp: Date
        let totalSize: UInt64
        let fileCount: Int
        let dirCount: Int
    }

    let rootPath: String
    let timestamp: Date
    let totalSize: UInt64
    let deltaBytes: Int64?
    let fileCount: Int
    let dirCount: Int
    let duration: TimeInterval

    var id: Key {
        Key(
            rootPath: rootPath,
            timestamp: timestamp,
            totalSize: totalSize,
            fileCount: fileCount,
            dirCount: dirCount
        )
    }

    var formattedDate: String {
        timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedSize: String {
        SizeFormatter.format(totalSize)
    }

    var formattedDeltaText: String {
        ScanHistoryMath.formattedSignedDelta(deltaBytes)
    }

    init(record: ScanRecord, deltaBytes: Int64?) {
        self.rootPath = record.rootPath
        self.timestamp = record.timestamp
        self.totalSize = record.totalSize
        self.deltaBytes = deltaBytes
        self.fileCount = record.fileCount
        self.dirCount = record.dirCount
        self.duration = record.duration
    }

    func matches(_ record: ScanRecord) -> Bool {
        id.rootPath == record.rootPath &&
        id.timestamp == record.timestamp &&
        id.totalSize == record.totalSize &&
        id.fileCount == record.fileCount &&
        id.dirCount == record.dirCount
    }
}

struct HistoryPathGroup: Identifiable, Equatable {
    let rootPath: String
    let rows: [HistoryScanRow]

    var id: String { rootPath }

    var latestTimestamp: Date {
        rows.first?.timestamp ?? .distantPast
    }
}

enum ScanHistoryBrowserModel {
    static func groupedHistoryRows(from records: [ScanRecord]) -> [HistoryPathGroup] {
        Dictionary(grouping: records, by: \.rootPath)
            .map { rootPath, groupedRecords in
                let sortedRecords = groupedRecords.sorted(by: newestFirst)
                let rows = sortedRecords.enumerated().map { index, record in
                    let previousRecord = index + 1 < sortedRecords.count ? sortedRecords[index + 1] : nil
                    let deltaBytes = previousRecord.map {
                        ScanHistoryMath.deltaBytes(current: record.totalSize, previous: $0.totalSize)
                    }

                    return HistoryScanRow(record: record, deltaBytes: deltaBytes)
                }

                return HistoryPathGroup(rootPath: rootPath, rows: rows)
            }
            .sorted { lhs, rhs in
                if lhs.latestTimestamp != rhs.latestTimestamp {
                    return lhs.latestTimestamp > rhs.latestTimestamp
                }

                return lhs.rootPath.localizedStandardCompare(rhs.rootPath) == .orderedAscending
            }
    }

    static func historyPreviewSnapshots(from record: ScanRecord) throws -> [HistoryPreviewSnapshot] {
        try record.decodedTopChildren().map { snapshot in
            HistoryPreviewSnapshot(
                name: snapshot.name,
                size: snapshot.size,
                isDirectory: snapshot.isDirectory
            )
        }
    }

    private static func newestFirst(_ lhs: ScanRecord, _ rhs: ScanRecord) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }

        if lhs.totalSize != rhs.totalSize {
            return lhs.totalSize > rhs.totalSize
        }

        return lhs.fileCount > rhs.fileCount
    }
}

struct HistoryPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\ScanRecord.timestamp, order: .reverse)]) private var records: [ScanRecord]
    @State private var selectedRowID: HistoryScanRow.Key?

    private var historyGroups: [HistoryPathGroup] {
        ScanHistoryBrowserModel.groupedHistoryRows(from: records)
    }

    private var selectionKeys: [HistoryScanRow.Key] {
        historyGroups.flatMap { group in
            group.rows.map(\.id)
        }
    }

    private var selectedRow: HistoryScanRow? {
        if let selectedRowID {
            for group in historyGroups {
                if let row = group.rows.first(where: { $0.id == selectedRowID }) {
                    return row
                }
            }
        }

        return historyGroups.first?.rows.first
    }

    private var selectedRecord: ScanRecord? {
        guard let selectedRow else { return nil }
        return records.first(where: selectedRow.matches)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if historyGroups.isEmpty {
                ContentUnavailableView(
                    "No Scan History Yet",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    description: Text("Complete a scan to browse past results and cached top-level snapshots.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    historyList
                        .frame(minWidth: 340, idealWidth: 380, maxWidth: 460)

                    historyDetail
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .onAppear {
            syncSelection()
        }
        .onChange(of: selectionKeys) { _, _ in
            syncSelection()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scan History")
                    .font(.title2.weight(.semibold))

                Text("Browse persisted scans and inspect cached top-level snapshots without changing the live view.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.regularMaterial)
    }

    private var historyList: some View {
        List(selection: $selectedRowID) {
            ForEach(historyGroups) { group in
                Section {
                    ForEach(group.rows) { row in
                        HistoryRowView(row: row)
                            .tag(row.id)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.rootPath)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text("\(group.rows.count) \(group.rows.count == 1 ? "scan" : "scans")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ViewBuilder
    private var historyDetail: some View {
        if let selectedRecord {
            HistoryRecordDetail(record: selectedRecord)
        } else {
            ContentUnavailableView(
                "Select a Scan",
                systemImage: "sidebar.left",
                description: Text("Choose a history row to preview the cached top-level snapshot.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func syncSelection() {
        guard let firstSelection = selectionKeys.first else {
            selectedRowID = nil
            return
        }

        guard let selectedRowID else {
            self.selectedRowID = firstSelection
            return
        }

        if !selectionKeys.contains(selectedRowID) {
            self.selectedRowID = firstSelection
        }
    }
}

private struct HistoryRowView: View {
    let row: HistoryScanRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.formattedDate)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 8) {
                Text(row.formattedSize)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text(row.formattedDeltaText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(deltaColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var deltaColor: Color {
        guard let deltaBytes = row.deltaBytes else { return .secondary }

        if deltaBytes > 0 {
            return .red
        }

        if deltaBytes < 0 {
            return .green
        }

        return .secondary
    }
}

private struct HistoryRecordDetail: View {
    let record: ScanRecord

    private enum PreviewState {
        case loaded([HistoryPreviewSnapshot])
        case empty
        case malformed
    }

    private var previewState: PreviewState {
        do {
            let snapshots = try ScanHistoryBrowserModel.historyPreviewSnapshots(from: record)
            return snapshots.isEmpty ? .empty : .loaded(snapshots)
        } catch {
            return .malformed
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow("Root Path", value: record.rootPath, monospaced: false, truncateMiddle: true)
                        detailRow("Scan Date", value: record.timestamp.formatted(date: .abbreviated, time: .standard))
                        detailRow("Total Size", value: SizeFormatter.format(record.totalSize))
                        detailRow("File Count", value: record.fileCount.formatted())
                        detailRow("Directory Count", value: record.dirCount.formatted())
                        detailRow("Scan Duration", value: formatDuration(record.duration))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Scan Details", systemImage: "clock")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Cached top-level snapshot only")
                            .font(.headline)

                        Text("This preview replays the persisted top-level children from the selected scan. It does not restore deeper descendants or replace the live scan tree.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        previewContent
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Snapshot Preview", systemImage: "square.stack.3d.up")
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var previewContent: some View {
        switch previewState {
        case .loaded(let snapshots):
            VStack(spacing: 10) {
                ForEach(snapshots) { snapshot in
                    HStack(spacing: 10) {
                        Image(systemName: snapshot.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(snapshot.isDirectory ? Color.accentColor : .secondary)
                            .frame(width: 16)

                        Text(snapshot.name)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text(snapshot.formattedSize)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }
        case .empty:
            ContentUnavailableView(
                "No Top-Level Snapshot",
                systemImage: "square.stack.3d.up.slash",
                description: Text("This scan did not persist any top-level child entries.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        case .malformed:
            ContentUnavailableView(
                "Snapshot Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The cached top-level snapshot could not be decoded.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }

    private func detailRow(
        _ title: String,
        value: String,
        monospaced: Bool = true,
        truncateMiddle: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .lineLimit(1)
                .truncationMode(truncateMiddle ? .middle : .tail)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int((duration * 1_000).rounded())) ms"
        }

        if duration < 60 {
            return String(format: "%.1f s", duration)
        }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
}
