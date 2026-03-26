import SwiftUI

struct InsightsToolbarPopoverButton: View {
    @Environment(AppState.self) private var appState
    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            Label("Insights", systemImage: "sparkles")
        }
        .help("Insights")
        .popover(
            isPresented: $isPopoverPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            InsightsPopover(
                insights: appState.scannerViewModel.insights,
                duplicateState: appState.scannerViewModel.duplicateReportState,
                onSelectNode: { node in
                    appState.selectInsight(node)
                    isPopoverPresented = false
                },
                onRunDuplicateScan: { forceRefresh in
                    appState.scannerViewModel.scanForDuplicates(forceRefresh: forceRefresh)
                },
                onSelectDuplicatePath: { path in
                    guard let node = appState.scannerViewModel.node(atPath: path) else { return }
                    appState.selectInsight(node)
                    isPopoverPresented = false
                },
                onMoveDuplicateToTrash: { path in
                    guard let node = appState.scannerViewModel.node(atPath: path) else { return }
                    appState.scannerViewModel.moveToTrash(node)
                }
            )
        }
        .onChange(of: appState.scannerViewModel.rootNode?.id) { _, rootID in
            if rootID == nil {
                isPopoverPresented = false
            }
        }
        .onChange(of: appState.scannerViewModel.isScanning) { _, isScanning in
            if isScanning {
                isPopoverPresented = false
            }
        }
    }
}

struct InsightsPopover: View {
    let insights: ScanInsights
    let duplicateState: DuplicateReportState
    let onSelectNode: (FileNode) -> Void
    let onRunDuplicateScan: (Bool) -> Void
    let onSelectDuplicatePath: (String) -> Void
    let onMoveDuplicateToTrash: (String) -> Void

    var body: some View {
        List {
            insightsSection(
                title: "Top Files",
                nodes: insights.topFiles,
                emptyState: "No files available in this scan."
            )
            insightsSection(
                title: "Top Directories",
                nodes: insights.topDirectories,
                emptyState: "No child directories available in this scan."
            )
            if let oldFiles = insights.oldFiles {
                oldFilesSection(report: oldFiles)
            }
            duplicatesSection
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(width: 560, height: 420)
    }

    @ViewBuilder
    private func insightsSection(
        title: String,
        nodes: [FileNode],
        emptyState: String
    ) -> some View {
        Section {
            if nodes.isEmpty {
                Text(emptyState)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(nodes) { node in
                    InsightRow(node: node) {
                        onSelectNode(node)
                    }
                }
            }
        } header: {
            Text(title)
        }
    }

    @ViewBuilder
    private func oldFilesSection(report: OldFileInsights) -> some View {
        Section {
            if report.hasResults {
                Text(report.summaryText)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                Text(report.emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            ForEach(report.directoryGroups) { group in
                OldFileDirectoryHeaderRow(group: group)

                ForEach(group.files) { node in
                    InsightRow(node: node) {
                        onSelectNode(node)
                    }
                    .padding(.leading, 12)
                }
            }
        } header: {
            Text("Old Files")
        }
    }

    private var duplicatesSection: some View {
        Section {
            HStack(spacing: 12) {
                Button(duplicateState.primaryActionTitle) {
                    onRunDuplicateScan(duplicateState.shouldForceRefresh)
                }
                .disabled(duplicateState.isLoading)

                if duplicateState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }
            .padding(.vertical, 4)

            switch duplicateState {
            case .idle:
                duplicatePlaceholderRow(
                    "Run an explicit duplicate scan to confirm repeated files from the completed scan tree."
                )
            case .loading:
                duplicatePlaceholderRow(
                    "Hashing duplicate candidates from the completed scan. You can keep using the rest of the app while this runs."
                )
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            case .loaded(let report):
                if let warningMessage = report.warningMessage {
                    Text(warningMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }

                if report.hasResults {
                    Text(report.summaryText)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)

                    ForEach(report.groups) { group in
                        DuplicateCard(
                            group: group,
                            onSelectPath: onSelectDuplicatePath,
                            onMoveToTrash: onMoveDuplicateToTrash
                        )
                    }
                } else {
                    duplicatePlaceholderRow(report.emptyStateText)
                }
            }
        } header: {
            Text("Duplicates")
        }
    }

    private func duplicatePlaceholderRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

private struct InsightRow: View {
    let node: FileNode
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: node.isDirectory ? "folder.fill" : node.category.icon)
                        .foregroundStyle(node.isDirectory ? FileCategory.folders.color : node.category.color)
                        .frame(width: 16)

                    Text(node.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 12)

                    Text(node.formattedSize)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(node.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(node.path.path)
    }
}

private struct OldFileDirectoryHeaderRow: View {
    let group: OldFileInsights.DirectoryGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(FileCategory.folders.color)
                    .frame(width: 16)

                Text(group.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 12)

                Text("\(group.fileCountText), \(SizeFormatter.format(group.totalSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(group.directoryPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 24)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
