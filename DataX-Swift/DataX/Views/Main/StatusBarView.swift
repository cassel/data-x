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
        .background(Color(nsColor: .controlBackgroundColor))
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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated scan icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 8) {
                Text("Scanning...")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let progress = appState.scannerViewModel.progress {
                    Text("\(progress.filesScanned.formatted()) files in \(progress.directoriesScanned.formatted()) folders")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Progress details
            if let progress = appState.scannerViewModel.progress {
                VStack(spacing: 16) {
                    // Linear progress indicator
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 300)

                    // Stats badges
                    HStack(spacing: 20) {
                        StatBadge(icon: "doc", value: "\(progress.filesScanned.formatted())", label: "Files")
                        StatBadge(icon: "folder", value: "\(progress.directoriesScanned.formatted())", label: "Folders")
                        StatBadge(icon: "internaldrive", value: progress.formattedBytes, label: "Size")
                        StatBadge(icon: "clock", value: progress.formattedElapsedTime, label: "Elapsed")
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

            Button("Cancel") {
                appState.scannerViewModel.cancelScan()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    VStack {
        StatusBarView()
    }
    .environment(AppState())
    .frame(width: 800, height: 100)
}
