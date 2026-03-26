import SwiftData
import SwiftUI

struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 16) {
            // Current folder info
            if let currentNode = appState.scannerViewModel.currentNode {
                folderInfoView(currentNode)
            }

            Spacer()

            // Disk info
            if let diskInfo = appState.scannerViewModel.diskInfo {
                diskInfoView(diskInfo)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .font(.system(size: 11))
    }

    @ViewBuilder
    private func folderInfoView(_ node: FileNode) -> some View {
        HStack(spacing: 12) {
            // Items count
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("\(node.fileCount.formatted()) items")
                    .foregroundColor(.secondary)
            }

            // Separator
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 3, height: 3)

            // Total size
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(node.formattedSize)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Children count (if directory with children)
            if node.isDirectory, let children = node.children, !children.isEmpty {
                // Separator
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 3, height: 3)

                HStack(spacing: 4) {
                    let dirCount = children.filter { $0.isDirectory }.count
                    let fileCount = children.filter { !$0.isDirectory }.count
                    Text("\(dirCount) folders, \(fileCount) files")
                        .foregroundColor(.secondary)
                }
            }

            StatusBarTrendSection(path: node.path.path)
        }
    }

    @ViewBuilder
    private func diskInfoView(_ diskInfo: DiskInfo) -> some View {
        HStack(spacing: 10) {
            // Volume name with icon
            HStack(spacing: 4) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(diskInfo.volumeName)
                    .foregroundColor(.secondary)
            }

            // Usage bar
            HStack(spacing: 8) {
                DiskUsageBar(
                    percentage: diskInfo.usedPercentage,
                    height: 4,
                    cornerRadius: 2
                )
                .frame(width: 60, height: 4)

                Text("\(diskInfo.formattedFree) free of \(diskInfo.formattedTotal)")
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct StatusBarTrendSection: View {
    let path: String

    @Query private var records: [ScanRecord]

    init(path: String) {
        self.path = path

        let rootPath = path
        _records = Query(
            filter: #Predicate<ScanRecord> { record in
                record.rootPath == rootPath
            },
            sort: [SortDescriptor(\ScanRecord.timestamp, order: .reverse)]
        )
    }

    private var separator: some View {
        Circle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 3, height: 3)
    }

    var body: some View {
        if let summary = ScanTrendSummaryBuilder.summary(from: records, matchingRootPath: path) {
            HStack(spacing: 12) {
                separator

                HStack(spacing: 8) {
                    TrendSparkline(points: summary.points)
                        .accessibilityValue(summary.accessibilityValue)

                    Text(summary.formattedDeltaText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(deltaColor(for: summary.deltaDirection))
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
        }
    }

    private func deltaColor(for direction: ScanTrendDirection) -> Color {
        switch direction {
        case .growth:
            .red
        case .reduction:
            .green
        case .neutral:
            .secondary
        }
    }
}

// MARK: - Scan Progress View

struct ScanProgressView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSymbolPulseActive = false
    let heroNamespace: Namespace.ID
    let usesSpatialHero: Bool

    private var motionPolicy: ScanProgressMotionPolicy {
        ScanProgressMotionPolicy(reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated scan icon
            ZStack {
                TransitionHeroShell(
                    size: 100,
                    fillOpacity: 0.1,
                    strokeOpacity: 0,
                    lineWidth: 0,
                    shadowOpacity: 0,
                    shadowRadius: 0,
                    namespace: heroNamespace,
                    usesSpatialHero: usesSpatialHero,
                    isSource: false
                )

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: isSymbolPulseActive)
                    .transition(.opacity)
            }

            VStack(spacing: 8) {
                Text("Scanning...")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let progress = appState.scannerViewModel.progress {
                    summaryView(progress)
                }
            }

            // Progress details
            if let progress = appState.scannerViewModel.progress {
                progressDetailsView(progress)
            }

            Button("Cancel") {
                appState.scannerViewModel.cancelScan()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isSymbolPulseActive = motionPolicy.allowsSymbolPulse
        }
        .onChange(of: reduceMotion) { _, newValue in
            isSymbolPulseActive = !newValue
        }
        .onDisappear {
            isSymbolPulseActive = false
        }
    }

    private func summaryView(_ progress: ScanProgress) -> some View {
        HStack(spacing: 0) {
            AnimatedNumericValueText(
                value: progress.filesScanned.formatted(),
                numericValue: Double(progress.filesScanned),
                motionPolicy: motionPolicy
            )
            Text(" files in ")
            AnimatedNumericValueText(
                value: progress.directoriesScanned.formatted(),
                numericValue: Double(progress.directoriesScanned),
                motionPolicy: motionPolicy
            )
            Text(" folders")
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func progressDetailsView(_ progress: ScanProgress) -> some View {
        let elapsedTime = progress.elapsedTime
        let elapsedValue = ScanProgressMotionPolicy.elapsedDisplayValue(for: elapsedTime)
        let elapsedText = ScanProgressMotionPolicy.formattedElapsedTime(for: elapsedTime)

        return VStack(spacing: 16) {
            // Linear progress indicator
            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 300)

            // Stats badges
            HStack(spacing: 20) {
                StatBadge(
                    icon: "doc",
                    value: progress.filesScanned.formatted(),
                    numericValue: Double(progress.filesScanned),
                    label: "Files",
                    motionPolicy: motionPolicy
                )
                StatBadge(
                    icon: "folder",
                    value: progress.directoriesScanned.formatted(),
                    numericValue: Double(progress.directoriesScanned),
                    label: "Folders",
                    motionPolicy: motionPolicy
                )
                StatBadge(
                    icon: "internaldrive",
                    value: progress.formattedBytes,
                    numericValue: Double(progress.bytesScanned),
                    label: "Size",
                    motionPolicy: motionPolicy
                )
                StatBadge(
                    icon: "clock",
                    value: elapsedText,
                    numericValue: elapsedValue,
                    label: "Elapsed",
                    motionPolicy: motionPolicy
                )
            }

            // Current path
            Text(progress.currentPath)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 400)
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let numericValue: Double
    let label: String
    let motionPolicy: ScanProgressMotionPolicy

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                AnimatedNumericValueText(
                    value: value,
                    numericValue: numericValue,
                    motionPolicy: motionPolicy
                )
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AnimatedNumericValueText: View {
    let value: String
    let numericValue: Double
    let motionPolicy: ScanProgressMotionPolicy

    var body: some View {
        Group {
            if motionPolicy.allowsNumericRoll {
                Text(value)
                    .contentTransition(.numericText(value: numericValue))
                    .animation(motionPolicy.numericRollAnimation, value: numericValue)
            } else {
                Text(value)
            }
        }
    }
}

struct ScanProgressMotionPolicy {
    static let numericRollDuration = 0.2

    let reduceMotion: Bool

    var allowsSymbolPulse: Bool {
        !reduceMotion
    }

    var allowsNumericRoll: Bool {
        !reduceMotion
    }

    var numericRollAnimation: Animation? {
        allowsNumericRoll ? .smooth(duration: Self.numericRollDuration) : nil
    }

    static func elapsedDisplayValue(for elapsedTime: TimeInterval) -> Double {
        Double(Int(elapsedTime))
    }

    static func formattedElapsedTime(for elapsedTime: TimeInterval) -> String {
        let seconds = Int(elapsedTime)

        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m \(seconds % 60)s"
        } else {
            return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        }
    }
}

@MainActor
private enum StatusBarPreviewData {
    static func makeAppState() -> AppState {
        let appState = AppState()
        let root = FileNode(url: URL(fileURLWithPath: "/Users/cassel/Projects/Data-X"), isDirectory: true)
        let docs = FileNode(url: URL(fileURLWithPath: "/Users/cassel/Projects/Data-X/docs"), isDirectory: true)
        docs.size = 1_024 * 1_024 * 3
        docs.fileCount = 12

        let readme = FileNode(
            url: URL(fileURLWithPath: "/Users/cassel/Projects/Data-X/README.md"),
            isDirectory: false,
            size: 1_024 * 120
        )

        root.children = [docs, readme]
        root.size = docs.size + readme.size
        root.fileCount = docs.fileCount + readme.fileCount

        appState.scannerViewModel.rootNode = root
        appState.scannerViewModel.currentNode = root
        appState.scannerViewModel.navigationStack = [root]
        appState.scannerViewModel.diskInfo = DiskInfo(
            totalSpace: 512 * 1_024 * 1_024 * 1_024,
            usedSpace: 356 * 1_024 * 1_024 * 1_024,
            freeSpace: 156 * 1_024 * 1_024 * 1_024,
            volumeName: "Macintosh HD",
            volumePath: URL(fileURLWithPath: "/")
        )
        return appState
    }

    static func makeModelContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: ScanRecord.self, configurations: configuration)
        let context = ModelContext(container)
        let rootPath = "/Users/cassel/Projects/Data-X"
        let sizes: [UInt64] = [
            5_100_000_000,
            5_400_000_000,
            5_650_000_000,
            6_050_000_000
        ]

        for (index, size) in sizes.enumerated() {
            context.insert(
                ScanRecord(
                    rootPath: rootPath,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index * 3_600)),
                    totalSize: size,
                    duration: 2,
                    fileCount: 120,
                    dirCount: 18,
                    topChildrenJSON: "[]"
                )
            )
        }

        context.insert(
            ScanRecord(
                rootPath: "/Users/cassel/Projects/Data-X/docs",
                timestamp: Date(timeIntervalSince1970: 1_700_010_000),
                totalSize: 2_200_000_000,
                duration: 1,
                fileCount: 40,
                dirCount: 6,
                topChildrenJSON: "[]"
            )
        )

        try! context.save()
        return container
    }
}

#Preview {
    let appState = StatusBarPreviewData.makeAppState()
    let container = StatusBarPreviewData.makeModelContainer()

    VStack {
        StatusBarView()
    }
    .environment(appState)
    .modelContainer(container)
    .frame(width: 800, height: 100)
}
