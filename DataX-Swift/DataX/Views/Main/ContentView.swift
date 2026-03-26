import AppKit
import SwiftUI

enum ContentViewPhase: Equatable {
    case welcome
    case scanning
    case scanned

    static func resolve(isScanning: Bool, rootNode: FileNode?) -> Self {
        if isScanning {
            return .scanning
        }

        if rootNode != nil {
            return .scanned
        }

        return .welcome
    }

    var minimumLeftPaneWidth: CGFloat {
        switch self {
        case .welcome:
            return 300
        case .scanning, .scanned:
            return 280
        }
    }

    var idealLeftPaneWidth: CGFloat? {
        switch self {
        case .welcome:
            return nil
        case .scanning:
            return 320
        case .scanned:
            return 350
        }
    }
}

enum SwipeNavigationIntent: Equatable {
    case back
    case ignore

    static func resolve(deltaX: CGFloat, deltaY: CGFloat, canNavigateBack: Bool) -> Self {
        guard canNavigateBack else { return .ignore }
        guard abs(deltaX) > abs(deltaY), deltaX != 0 else { return .ignore }

        return deltaX < 0 ? .back : .ignore
    }
}

enum VisualizationNavigationDirection: Equatable {
    case neutral
    case forward
    case backward

    static func resolve(fromDepth: Int, toDepth: Int) -> Self {
        if toDepth > fromDepth {
            return .forward
        }

        if toDepth < fromDepth {
            return .backward
        }

        return .neutral
    }

    var transition: AnyTransition {
        switch self {
        case .neutral:
            return .opacity
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}

struct ContentTransitionMotionPolicy {
    let reduceMotion: Bool

    var usesSpatialHero: Bool {
        !reduceMotion
    }

    var usesOpacityOnlyPhaseTransitions: Bool {
        reduceMotion
    }

    var usesDirectionalResultsPaneTransition: Bool {
        !reduceMotion
    }

    var usesDirectionalVisualizationNavigationTransition: Bool {
        !reduceMotion
    }

    var phaseAnimation: Animation {
        if usesOpacityOnlyPhaseTransitions {
            return .easeInOut(duration: 0.2)
        }

        return .spring(duration: 0.4)
    }

    var navigationAnimation: Animation {
        if reduceMotion {
            return .easeInOut(duration: 0.15)
        }

        return .easeInOut(duration: 0.24)
    }

    var handoffTransition: AnyTransition {
        .opacity
    }

    var resultsPaneTransition: AnyTransition {
        if usesDirectionalResultsPaneTransition {
            return .move(edge: .trailing).combined(with: .opacity)
        }

        return .opacity
    }

    func visualizationNavigationTransition(
        for direction: VisualizationNavigationDirection
    ) -> AnyTransition {
        if usesDirectionalVisualizationNavigationTransition {
            return direction.transition
        }

        return .opacity
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var transitionNamespace
    @State private var isLegendVisible = false
    @State private var visualizationNavigationDirection: VisualizationNavigationDirection = .neutral

    var body: some View {
        @Bindable var state = appState
        let contentPhase = ContentViewPhase.resolve(
            isScanning: state.scannerViewModel.isScanning,
            rootNode: state.scannerViewModel.rootNode
        )
        let treeMutationRevision = state.scannerViewModel.treeMutationRevision
        let motionPolicy = ContentTransitionMotionPolicy(reduceMotion: reduceMotion)

        HSplitView {
            leftPane(state: state, contentPhase: contentPhase, motionPolicy: motionPolicy)
            rightPane(
                state: state,
                contentPhase: contentPhase,
                treeMutationRevision: treeMutationRevision,
                motionPolicy: motionPolicy
            )
        }
        .animation(motionPolicy.phaseAnimation, value: contentPhase)
        .toolbar {
            scannedToolbar(state: state, contentPhase: contentPhase)
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

    private func leftPane(
        state: AppState,
        contentPhase: ContentViewPhase,
        motionPolicy: ContentTransitionMotionPolicy
    ) -> some View {
        ZStack {
            if contentPhase == .scanned, let rootNode = state.scannerViewModel.rootNode {
                FileTreePanel(
                    rootNode: rootNode,
                    currentNode: state.scannerViewModel.currentNode,
                    highlightedNode: Binding(
                        get: { state.highlightedNode },
                        set: { state.highlightedNode = $0 }
                    ),
                    onMoveToTrash: moveToTrashImmediately,
                    onNavigate: { node in
                        navigate(to: node, clearHighlight: true)
                    }
                )
                .transition(motionPolicy.handoffTransition)
            } else {
                ZStack {
                    WelcomeView(
                        heroNamespace: transitionNamespace,
                        usesSpatialHero: motionPolicy.usesSpatialHero,
                        isInteractive: contentPhase == .welcome
                    )
                    .opacity(contentPhase == .welcome ? 1 : 0)
                    .allowsHitTesting(contentPhase == .welcome)
                    .accessibilityHidden(contentPhase != .welcome)

                    if contentPhase == .scanning {
                        ScanProgressView(
                            heroNamespace: transitionNamespace,
                            usesSpatialHero: motionPolicy.usesSpatialHero
                        )
                        .transition(motionPolicy.handoffTransition)
                    }
                }
                .transition(motionPolicy.handoffTransition)
            }
        }
        .frame(
            minWidth: contentPhase.minimumLeftPaneWidth,
            idealWidth: contentPhase.idealLeftPaneWidth,
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .contentTransition(.opacity)
    }

    @ViewBuilder
    private func rightPane(
        state: AppState,
        contentPhase: ContentViewPhase,
        treeMutationRevision: Int,
        motionPolicy: ContentTransitionMotionPolicy
    ) -> some View {
        if let rootNode = state.scannerViewModel.rootNode {
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

                visualizationShell(
                    node: node,
                    treeMutationRevision: treeMutationRevision,
                    motionPolicy: motionPolicy
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                StatusBarView()
            }
            .frame(minWidth: 400)
            .background(.regularMaterial)
            .contentTransition(.opacity)
            .transition(motionPolicy.resultsPaneTransition)
        }
    }

    @ToolbarContentBuilder
    private func scannedToolbar(state: AppState, contentPhase: ContentViewPhase) -> some ToolbarContent {
        if contentPhase == .scanned,
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
        if state.scannerViewModel.isIncrementalScanInProgress {
            return .treemap
        }

        return state.selectedVisualization
    }

    private func preservesVisualizationIdentity(
        for visualization: AppState.VisualizationType
    ) -> Bool {
        visualization == .treemap
    }

    @ViewBuilder
    private func visualizationShell(
        node: FileNode,
        treeMutationRevision: Int,
        motionPolicy: ContentTransitionMotionPolicy
    ) -> some View {
        let visualization = visibleVisualization(for: appState)

        SwipeNavigationSurface(
            canNavigateBack: appState.scannerViewModel.canNavigateBack,
            onSwipeBack: handleSwipeBack
        ) {
            ZStack {
                if preservesVisualizationIdentity(for: visualization) {
                    mainVisualization(node: node, treeMutationRevision: treeMutationRevision)
                        .transition(
                            motionPolicy.visualizationNavigationTransition(
                                for: visualizationNavigationDirection
                            )
                        )
                } else {
                    mainVisualization(node: node, treeMutationRevision: treeMutationRevision)
                        .id(node.id)
                        .transition(
                            motionPolicy.visualizationNavigationTransition(
                                for: visualizationNavigationDirection
                            )
                        )
                }
            }
            .clipped()
            .animation(motionPolicy.navigationAnimation, value: node.id)
            .overlay(alignment: .topTrailing) {
                if isLegendVisible {
                    FileTypeLegendOverlay(node: node)
                        .padding(12)
                }
            }
        }
    }

    @ViewBuilder
    private func mainVisualization(node: FileNode, treeMutationRevision: Int) -> some View {
        switch visibleVisualization(for: appState) {
        case .treemap:
            TreemapView(
                node: node,
                highlightedNode: appState.highlightedNode,
                onSelect: { navigate(to: $0) },
                layoutRevision: treeMutationRevision,
                incrementalScanInProgress: appState.scannerViewModel.isIncrementalScanInProgress,
                onMoveToTrash: { appState.scannerViewModel.beginMoveToTrash($0) },
                onCommitMoveToTrash: commitMoveToTrash
            )
        case .sunburst:
            SunburstView(node: node) { navigate(to: $0) }
        }
    }

    private func navigate(to node: FileNode, clearHighlight: Bool = false) {
        guard node.isDirectory else { return }

        let currentDepth = appState.scannerViewModel.navigationStack.count
        let targetDepth = targetNavigationDepth(for: node, from: appState.scannerViewModel.navigationStack)
        visualizationNavigationDirection = VisualizationNavigationDirection.resolve(
            fromDepth: currentDepth,
            toDepth: targetDepth
        )

        withAnimation(ContentTransitionMotionPolicy(reduceMotion: reduceMotion).navigationAnimation) {
            appState.scannerViewModel.navigateTo(node)

            if clearHighlight {
                appState.highlightedNode = nil
            }
        }
    }

    private func handleSwipeBack() {
        guard appState.scannerViewModel.canNavigateBack else { return }

        visualizationNavigationDirection = .backward

        withAnimation(ContentTransitionMotionPolicy(reduceMotion: reduceMotion).navigationAnimation) {
            appState.scannerViewModel.navigateBack()
        }
    }

    private func targetNavigationDepth(for node: FileNode, from navigationStack: [FileNode]) -> Int {
        if let index = navigationStack.firstIndex(where: { $0.id == node.id }) {
            return index + 1
        }

        return navigationStack.count + 1
    }

    private func moveToTrashImmediately(_ node: FileNode) {
        guard appState.scannerViewModel.beginMoveToTrash(node) else { return }
        commitMoveToTrash(node)
    }

    private func commitMoveToTrash(_ node: FileNode) {
        clearHighlightIfNeeded(forRemovedNode: node)
        appState.scannerViewModel.commitMoveToTrash(node)
    }

    private func clearHighlightIfNeeded(forRemovedNode node: FileNode) {
        guard let highlightedNode = appState.highlightedNode,
              node.containsNode(withID: highlightedNode.id) else {
            return
        }

        appState.highlightedNode = nil
    }
}

private struct SwipeNavigationSurface<Content: View>: NSViewRepresentable {
    let canNavigateBack: Bool
    let onSwipeBack: () -> Void
    let content: Content

    init(
        canNavigateBack: Bool,
        onSwipeBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.canNavigateBack = canNavigateBack
        self.onSwipeBack = onSwipeBack
        self.content = content()
    }

    func makeNSView(context: Context) -> SwipeNavigationHostingView<Content> {
        let view = SwipeNavigationHostingView(rootView: content)
        view.canNavigateBack = canNavigateBack
        view.onSwipeBack = onSwipeBack
        return view
    }

    func updateNSView(_ nsView: SwipeNavigationHostingView<Content>, context: Context) {
        nsView.rootView = content
        nsView.canNavigateBack = canNavigateBack
        nsView.onSwipeBack = onSwipeBack
    }
}

private final class SwipeNavigationHostingView<Content: View>: NSHostingView<Content> {
    var canNavigateBack = false
    var onSwipeBack: (() -> Void)?
    private var handledSwipeInCurrentSequence = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func swipe(with event: NSEvent) {
        let isDiscreteEvent = event.phase.isEmpty || event.phase.contains(.ended) || event.phase.contains(.cancelled)

        if event.phase.contains(.began) {
            handledSwipeInCurrentSequence = false
        }

        let intent = SwipeNavigationIntent.resolve(
            deltaX: event.deltaX,
            deltaY: event.deltaY,
            canNavigateBack: canNavigateBack
        )

        if intent == .back, !handledSwipeInCurrentSequence {
            handledSwipeInCurrentSequence = !isDiscreteEvent
            onSwipeBack?()
        }

        if isDiscreteEvent {
            handledSwipeInCurrentSequence = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - File Tree Panel (Center)

struct FileTreePanel: View {
    let rootNode: FileNode
    let currentNode: FileNode?  // Currently navigated node (shown in visualization)
    @Binding var highlightedNode: FileNode?  // Selected in tree (highlighted in treemap)
    let onMoveToTrash: (FileNode) -> Void
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
                    onMoveToTrash: onMoveToTrash,
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
    let onMoveToTrash: (FileNode) -> Void
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
                                onMoveToTrash: onMoveToTrash,
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
            onMoveToTrash(node)
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
