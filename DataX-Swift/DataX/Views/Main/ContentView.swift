import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var isLegendVisible = false
    private let welcomeTransition = AnyTransition.opacity.combined(with: .scale(scale: 0.98))
    private let scanTransition = AnyTransition.opacity.combined(with: .scale(scale: 1.02))

    var body: some View {
        @Bindable var state = appState

        HSplitView {
            leftPane(state: state)
            rightPane(state: state)
        }
        .animation(.easeInOut(duration: 0.3), value: state.scannerViewModel.isScanning)
        .animation(.easeInOut(duration: 0.3), value: state.scannerViewModel.rootNode != nil)
        .toolbar {
            scannedToolbar(state: state)
        }
        .fileImporter(
            isPresented: $state.showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            state.handleFolderImport(result)
        }
        .onChange(of: state.scannerViewModel.rootNode?.id) { _, _ in
            isLegendVisible = false
        }
        .alert(
            "Scan Failed",
            isPresented: Binding(
                get: { state.scannerViewModel.error != nil || state.sshViewModel.error != nil },
                set: { if !$0 { state.scannerViewModel.error = nil; state.sshViewModel.error = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.sshViewModel.error ?? state.scannerViewModel.error?.localizedDescription ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func leftPane(state: AppState) -> some View {
        if state.scannerViewModel.isScanning {
            ScanProgressView()
                .frame(minWidth: 280, idealWidth: 320)
                .transition(scanTransition)
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
            .transition(.opacity)
        } else {
            WelcomeView()
                .frame(minWidth: 300)
                .transition(welcomeTransition)
        }
    }

    @ViewBuilder
    private func rightPane(state: AppState) -> some View {
        if !state.scannerViewModel.isScanning,
           let rootNode = state.scannerViewModel.rootNode {
            let node = state.scannerViewModel.currentNode ?? rootNode

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: visibleVisualization(for: state).icon)
                        .foregroundColor(.accentColor)
                    Text(visibleVisualization(for: state).rawValue)
                        .font(.headline)

                    Spacer()

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
                .background(.ultraThinMaterial)

                Divider()

                mainVisualization(node: node)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        if isLegendVisible {
                            FileTypeLegendOverlay(node: node)
                                .padding(12)
                        }
                    }

                Divider()

                StatusBarView()
            }
            .frame(minWidth: 400)
            .background(.regularMaterial)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private func scannedToolbar(state: AppState) -> some ToolbarContent {
        if !state.scannerViewModel.isScanning,
           state.scannerViewModel.rootNode != nil {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    state.returnHome()
                } label: {
                    Image(systemName: "house")
                }
                .help("Back to Home")

                Button {
                    state.showFolderPicker = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Open Folder")
            }

            ToolbarItem(placement: .principal) {
                Picker(
                    "Visualization",
                    selection: Binding(
                        get: { visibleVisualization(for: state) },
                        set: { state.selectedVisualization = $0 }
                    )
                ) {
                    ForEach(AppState.VisualizationType.toolbarOptions) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 420)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isLegendVisible.toggle()
                } label: {
                    Image(systemName: isLegendVisible ? "list.bullet.rectangle.portrait.fill" : "list.bullet.rectangle.portrait")
                }
                .help(isLegendVisible ? "Hide File Type Legend" : "Show File Type Legend")

                SSHToolbarPopoverButton()

                if let node = state.scannerViewModel.currentNode ?? state.scannerViewModel.rootNode {
                    Button {
                        FileOperationsService.revealInFinder(node.path)
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                    .help("Reveal in Finder")
                }

                Button {
                    state.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    private func visibleVisualization(for state: AppState) -> AppState.VisualizationType {
        state.selectedVisualization == .fileTree ? .treemap : state.selectedVisualization
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
            .background(.ultraThinMaterial)

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
        .background(.regularMaterial)
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
