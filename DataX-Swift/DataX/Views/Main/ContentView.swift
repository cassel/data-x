import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        HSplitView {
            // Left - File Tree (always visible)
            if state.scannerViewModel.isScanning {
                ScanProgressView()
                    .frame(minWidth: 280, idealWidth: 320)
            } else if let rootNode = state.scannerViewModel.rootNode {
                FileTreePanel(
                    rootNode: rootNode,
                    currentNode: state.scannerViewModel.currentNode,
                    highlightedNode: Binding(
                        get: { state.highlightedNode },
                        set: { state.highlightedNode = $0 }
                    ),
                    onNavigate: { node in
                        state.scannerViewModel.navigateTo(node)
                        state.highlightedNode = nil  // Clear highlight when navigating
                    }
                )
                .frame(minWidth: 280, idealWidth: 350)
            } else {
                WelcomeView()
                    .frame(minWidth: 300)
            }

            // Right - Visualization + Sidebar
            if !state.scannerViewModel.isScanning {
                if let node = state.scannerViewModel.currentNode {
                    HSplitView {
                        // Visualization
                        VStack(spacing: 0) {
                            // Visualization header
                            HStack {
                                Image(systemName: state.selectedVisualization.icon)
                                    .foregroundColor(.accentColor)
                                Text(state.selectedVisualization.rawValue)
                                    .font(.headline)

                                Spacer()

                                // Breadcrumb for current folder
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(node.name)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(nsColor: .controlBackgroundColor))

                            Divider()

                            // Visualization content
                            mainVisualization(node: node)

                            Divider()

                            // Status bar
                            StatusBarView()
                        }
                        .frame(minWidth: 400)

                        // Right Sidebar - Visualizations & Stats
                        SidebarView()
                            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $state.showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                state.scan(directory: url)
            }
        }
    }

    @ViewBuilder
    private func mainVisualization(node: FileNode) -> some View {
        switch appState.selectedVisualization {
        case .treemap:
            TreemapView(node: node, highlightedNode: appState.highlightedNode) { appState.scannerViewModel.navigateTo($0) }
        case .sunburst:
            SunburstView(node: node) { appState.scannerViewModel.navigateTo($0) }
        case .icicle:
            IcicleView(node: node) { appState.scannerViewModel.navigateTo($0) }
        case .barChart:
            BarChartView(node: node) { appState.scannerViewModel.navigateTo($0) }
        case .circlePacking:
            CirclePackingView(node: node) { appState.scannerViewModel.navigateTo($0) }
        case .fileTree:
            TreemapView(node: node, highlightedNode: appState.highlightedNode) { appState.scannerViewModel.navigateTo($0) }
        }
    }
}

// MARK: - File Tree Panel (Center)

struct FileTreePanel: View {
    let rootNode: FileNode
    let currentNode: FileNode?  // Currently navigated node (shown in visualization)
    @Binding var highlightedNode: FileNode?  // Selected in tree (highlighted in treemap)
    let onNavigate: (FileNode) -> Void  // Double-click to navigate

    @State private var expandedNodes: Set<UUID> = []
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                Text("File Browser")
                    .font(.headline)

                Spacer()

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 120)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Breadcrumb - shows current navigated path
            BreadcrumbView(node: currentNode ?? rootNode, rootNode: rootNode) { node in
                onNavigate(node)
            }

            Divider()

            // File tree
            List {
                FileTreeNode(
                    node: rootNode,
                    highlightedNode: $highlightedNode,
                    expandedNodes: $expandedNodes,
                    searchText: searchText,
                    level: 0,
                    onNavigate: onNavigate
                )
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

// MARK: - Breadcrumb View

struct BreadcrumbView: View {
    let node: FileNode
    let rootNode: FileNode
    let onSelect: (FileNode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let path = buildPath(to: node, from: rootNode)

                ForEach(Array(path.enumerated()), id: \.element.id) { index, pathNode in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        onSelect(pathNode)
                    } label: {
                        HStack(spacing: 4) {
                            if index == 0 {
                                Image(systemName: "house.fill")
                                    .font(.caption)
                            }
                            Text(pathNode.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func buildPath(to target: FileNode, from root: FileNode) -> [FileNode] {
        var path: [FileNode] = []

        func find(node: FileNode, target: FileNode) -> Bool {
            if node.id == target.id {
                path.append(node)
                return true
            }
            for child in node.children ?? [] {
                if find(node: child, target: target) {
                    path.insert(node, at: 0)
                    return true
                }
            }
            return false
        }

        _ = find(node: root, target: target)
        return path.isEmpty ? [root] : path
    }
}

// MARK: - File Tree Node

struct FileTreeNode: View {
    let node: FileNode
    @Binding var highlightedNode: FileNode?  // Single click highlights
    @Binding var expandedNodes: Set<UUID>
    let searchText: String
    let level: Int
    let onNavigate: (FileNode) -> Void  // Double click navigates

    private var isExpanded: Bool {
        expandedNodes.contains(node.id)
    }

    private var isHighlighted: Bool {
        highlightedNode?.id == node.id
    }

    private var matchesSearch: Bool {
        searchText.isEmpty || node.name.localizedCaseInsensitiveContains(searchText)
    }

    private var hasMatchingChildren: Bool {
        guard !searchText.isEmpty else { return true }
        return node.children?.contains { child in
            child.name.localizedCaseInsensitiveContains(searchText) ||
            (child.isDirectory && hasMatchingDescendants(child))
        } ?? false
    }

    private func hasMatchingDescendants(_ node: FileNode) -> Bool {
        node.children?.contains { child in
            child.name.localizedCaseInsensitiveContains(searchText) ||
            (child.isDirectory && hasMatchingDescendants(child))
        } ?? false
    }

    var body: some View {
        if matchesSearch || hasMatchingChildren {
            if node.isDirectory && !(node.children?.isEmpty ?? true) {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { isExpanded || !searchText.isEmpty },
                        set: { newValue in
                            if newValue {
                                expandedNodes.insert(node.id)
                            } else {
                                expandedNodes.remove(node.id)
                            }
                        }
                    )
                ) {
                    if let children = node.sortedChildren {
                        ForEach(children) { child in
                            FileTreeNode(
                                node: child,
                                highlightedNode: $highlightedNode,
                                expandedNodes: $expandedNodes,
                                searchText: searchText,
                                level: level + 1,
                                onNavigate: onNavigate
                            )
                        }
                    }
                } label: {
                    nodeRow
                }
            } else {
                nodeRow
            }
        }
    }

    @ViewBuilder
    private var nodeRow: some View {
        HStack(spacing: 8) {
            // Icon with color
            Image(systemName: node.isDirectory ? "folder.fill" : node.category.icon)
                .foregroundColor(node.isDirectory ? FileCategory.folders.color : node.category.color)
                .frame(width: 18)

            // Name
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(matchesSearch || searchText.isEmpty ? .primary : .secondary)

            Spacer()

            // Size
            Text(node.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            // Item count for directories
            if node.isDirectory && node.fileCount > 0 {
                Text("\(node.fileCount)")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.5))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(isHighlighted ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double click: navigate into folder or open file
            if node.isDirectory {
                onNavigate(node)
            } else {
                FileOperationsService.openFile(node.path)
            }
        }
        .onTapGesture(count: 1) {
            // Single click: highlight in treemap (directories only)
            if node.isDirectory {
                highlightedNode = node
            }
        }
        .contextMenu {
            contextMenuItems
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if node.isDirectory {
            Button {
                onNavigate(node)
            } label: {
                Label("Open Folder", systemImage: "folder")
            }

            Button {
                highlightedNode = node
            } label: {
                Label("Highlight in Visualization", systemImage: "chart.pie")
            }

            Divider()
        }

        Button {
            FileOperationsService.revealInFinder(node.path)
        } label: {
            Label("Reveal in Finder", systemImage: "folder.badge.gearshape")
        }

        Button {
            FileOperationsService.openFile(node.path)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }

        Divider()

        Button {
            FileOperationsService.copyPath(node.path)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        if node.isDirectory {
            Button {
                FileOperationsService.openInTerminal(node.path)
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }
        }

        Divider()

        Button(role: .destructive) {
            try? FileOperationsService.moveToTrash(node.path)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 0) {
            // App header
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Data-X")
                    .font(.headline)
                Spacer()

                Button {
                    state.showFolderPicker = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .help("Open Folder")
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Visualizations section
            SidebarSectionHeader(title: "Visualizations")

            ForEach(AppState.VisualizationType.allCases.filter { $0 != .fileTree }) { type in
                SidebarButton(
                    icon: type.icon,
                    label: type.rawValue,
                    isSelected: state.selectedVisualization == type
                ) {
                    state.selectedVisualization = type
                }
            }

            Divider()
                .padding(.vertical, 8)

            // File Types section (only show when we have data)
            if let node = state.scannerViewModel.currentNode {
                SidebarSectionHeader(title: "File Types")

                ScrollView {
                    VStack(spacing: 0) {
                        let stats = calculateCategoryStats(from: node)
                        ForEach(stats.filter { $0.size > 0 }, id: \.category) { stat in
                            CategoryStatRow(stat: stat, totalSize: node.size)
                        }
                    }
                }
            }

            Spacer()

            Divider()

            // Quick actions
            if state.scannerViewModel.rootNode != nil {
                HStack(spacing: 12) {
                    Button {
                        state.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")

                    if let node = state.scannerViewModel.currentNode {
                        Button {
                            FileOperationsService.revealInFinder(node.path)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }

                    Spacer()
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func calculateCategoryStats(from node: FileNode) -> [CategoryStat] {
        var categorySizes: [FileCategory: UInt64] = [:]
        var categoryCounts: [FileCategory: Int] = [:]

        func traverse(_ n: FileNode) {
            if n.isDirectory {
                n.children?.forEach { traverse($0) }
            } else {
                let cat = n.category
                categorySizes[cat, default: 0] += n.size
                categoryCounts[cat, default: 0] += 1
            }
        }

        traverse(node)

        return FileCategory.allCases.map { cat in
            CategoryStat(
                category: cat,
                size: categorySizes[cat] ?? 0,
                count: categoryCounts[cat] ?? 0
            )
        }.sorted { $0.size > $1.size }
    }
}

struct CategoryStat {
    let category: FileCategory
    let size: UInt64
    let count: Int
}

struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
    }
}

struct SidebarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

struct CategoryStatRow: View {
    let stat: CategoryStat
    let totalSize: UInt64

    private var percentage: Double {
        guard totalSize > 0 else { return 0 }
        return Double(stat.size) / Double(totalSize)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                // Color indicator
                Circle()
                    .fill(stat.category.color)
                    .frame(width: 8, height: 8)

                // Category name
                Text(stat.category.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Size
                Text(SizeFormatter.format(stat.size))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(stat.category.color)
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("Data-X")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Disk Space Analyzer")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Text("Visualize disk usage and find what's taking up space")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)

            Button {
                appState.showFolderPicker = true
            } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Keyboard shortcut hint
            Text("⌘O")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, -8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("treemapDepth") private var treemapDepth = 1

    var body: some View {
        Form {
            Picker("Treemap depth", selection: $treemapDepth) {
                Text("1 level").tag(1)
                Text("2 levels").tag(2)
                Text("3 levels").tag(3)
            }
        }
        .padding()
        .frame(width: 300, height: 150)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1200, height: 700)
}
