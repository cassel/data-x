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
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(usageColor(diskInfo.usedPercentage))
                            .frame(width: max(0, geometry.size.width * diskInfo.usedPercentage / 100), height: 4)
                    }
                }
                .frame(width: 60, height: 4)

                Text("\(diskInfo.formattedFree) free of \(diskInfo.formattedTotal)")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func usageColor(_ percentage: Double) -> Color {
        if percentage > 90 {
            return .red
        } else if percentage > 75 {
            return .orange
        } else {
            return .accentColor
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

#Preview {
    VStack {
        StatusBarView()
    }
    .environment(AppState())
    .frame(width: 800, height: 100)
}
