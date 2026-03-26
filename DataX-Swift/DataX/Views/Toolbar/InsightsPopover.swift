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
            InsightsPopover(insights: appState.scannerViewModel.insights) { node in
                appState.selectInsight(node)
                isPopoverPresented = false
            }
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
    let onSelectNode: (FileNode) -> Void

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
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(width: 520, height: 360)
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
