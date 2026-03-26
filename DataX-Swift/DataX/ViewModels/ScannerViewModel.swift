import Foundation
import SwiftUI

@MainActor
@Observable
final class ScannerViewModel {
    // MARK: - State

    var rootNode: FileNode?
    var currentNode: FileNode?
    var navigationStack: [FileNode] = []
    var isScanning = false
    var isIncrementalScanInProgress = false
    var progress: ScanProgress?
    var diskInfo: DiskInfo?
    var error: Error?
    var searchQuery = ""
    var searchResults: [FileNode] = []
    var treeMutationRevision = 0

    // MARK: - Private

    @ObservationIgnored private var scanner = ScannerService()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var activeScanSessionID: UUID?
    @ObservationIgnored private var stableNodeIDsByPath: [String: UUID] = [:]

    // MARK: - Computed Properties

    var canNavigateBack: Bool {
        !isIncrementalScanInProgress && navigationStack.count > 1
    }

    var currentPath: String {
        currentNode?.path.path ?? ""
    }

    var breadcrumbs: [FileNode] {
        navigationStack
    }

    var displayedChildren: [FileNode]? {
        if isIncrementalScanInProgress {
            return currentNode?.sortedChildren
        }

        if !searchQuery.isEmpty {
            return searchResults
        }

        return currentNode?.sortedChildren
    }

    // MARK: - Actions

    func scan(directory: URL) {
        cancelActiveLocalScan(resetScanningState: false)

        let sessionID = UUID()
        let startTime = Date()
        let standardizedDirectory = directory.standardizedFileURL
        let directoryName = Self.displayName(for: standardizedDirectory)
        let scanner = ScannerService()

        self.scanner = scanner
        activeScanSessionID = sessionID
        isScanning = true
        isIncrementalScanInProgress = true
        error = nil
        progress = ScanProgress(
            filesScanned: 0,
            directoriesScanned: 0,
            bytesScanned: 0,
            currentPath: directoryName,
            startTime: startTime,
            isComplete: false
        )
        resetSearch()
        diskInfo = try? DiskInfo.forPath(standardizedDirectory)
        prepareIncrementalRoot(for: standardizedDirectory)

        scanTask = Task { [weak self, scanner, standardizedDirectory] in
            guard let self else {
                await scanner.cancel()
                return
            }

            let events = await scanner.scan(directory: standardizedDirectory)
            var didComplete = false

            for await event in events {
                guard !Task.isCancelled else { break }
                guard self.activeScanSessionID == sessionID else { break }

                if case .complete = event {
                    didComplete = true
                }

                self.handleLocalScanEvent(event, sessionID: sessionID)
            }

            guard self.activeScanSessionID == sessionID else { return }
            guard !didComplete else { return }

            self.finishCancelledLocalScan(sessionID: sessionID)
        }
    }

    func cancelScan() {
        if activeScanSessionID != nil {
            cancelActiveLocalScan(resetScanningState: true)
            return
        }

        isScanning = false
        progress = nil
    }

    func navigateTo(_ node: FileNode) {
        guard !isIncrementalScanInProgress, node.isDirectory else { return }

        currentNode = node
        searchQuery = ""
        searchResults = []

        if let index = navigationStack.firstIndex(where: { $0.id == node.id }) {
            navigationStack = Array(navigationStack.prefix(through: index))
        } else {
            navigationStack.append(node)
        }
    }

    func navigateBack() {
        guard !isIncrementalScanInProgress, navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        currentNode = navigationStack.last
        searchQuery = ""
        searchResults = []
    }

    func navigateToRoot() {
        guard !isIncrementalScanInProgress, let root = rootNode else { return }
        currentNode = root
        navigationStack = [root]
        searchQuery = ""
        searchResults = []
    }

    func navigateToBreadcrumb(at index: Int) {
        guard !isIncrementalScanInProgress, index < navigationStack.count else { return }
        let node = navigationStack[index]
        currentNode = node
        navigationStack = Array(navigationStack.prefix(through: index))
        searchQuery = ""
        searchResults = []
    }

    // MARK: - Search

    func performSearch(_ query: String) {
        guard !isIncrementalScanInProgress else {
            resetSearch()
            return
        }

        searchQuery = query

        guard !query.isEmpty, let root = currentNode else {
            searchResults = []
            return
        }

        let lowercasedQuery = query.lowercased()
        var results: [FileNode] = []

        func searchNode(_ node: FileNode) {
            if node.name.lowercased().contains(lowercasedQuery) {
                results.append(node)
            }
            node.children?.forEach { searchNode($0) }
        }

        searchNode(root)
        searchResults = results.sorted { $0.size > $1.size }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
    }

    // MARK: - File Operations

    func revealInFinder(_ node: FileNode) {
        FileOperationsService.revealInFinder(node.path)
    }

    @discardableResult
    func beginMoveToTrash(_ node: FileNode) -> Bool {
        error = nil

        do {
            try FileOperationsService.moveToTrash(node.path)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    func commitMoveToTrash(_ node: FileNode) {
        commitNodeRemoval(node)
    }

    func moveToTrash(_ node: FileNode) {
        guard beginMoveToTrash(node) else {
            return
        }

        commitMoveToTrash(node)
    }

    func deleteFile(_ node: FileNode) {
        error = nil

        do {
            try FileOperationsService.delete(node.path)
            commitNodeRemoval(node)
        } catch {
            self.error = error
        }
    }

    func openFile(_ node: FileNode) {
        FileOperationsService.openFile(node.path)
    }

    func openInTerminal(_ node: FileNode) {
        FileOperationsService.openInTerminal(node.path)
    }

    func copyPath(_ node: FileNode) {
        FileOperationsService.copyPath(node.path)
    }

    func beginRemoteScan() {
        cancelActiveLocalScan(resetScanningState: false)
        clearVisibleTree(resetIdentityState: true)
        isScanning = true
        isIncrementalScanInProgress = false
        error = nil
        progress = .initial
        resetSearch()
    }

    func updateRemoteProgress(_ newProgress: ScanProgress) {
        progress = newProgress
    }

    func completeRemoteScan(with root: FileNode) {
        rootNode = root
        currentNode = root
        navigationStack = [root]
        isScanning = false
        isIncrementalScanInProgress = false
        error = nil
        treeMutationRevision += 1
    }

    func failRemoteScan(with error: Error) {
        self.error = error
        isScanning = false
        isIncrementalScanInProgress = false
        progress = nil
    }

    // MARK: - Private Helpers

    private static func displayName(for directory: URL) -> String {
        let name = directory.lastPathComponent
        return name.isEmpty ? directory.path : name
    }

    private func cancelActiveLocalScan(resetScanningState: Bool) {
        let scanner = self.scanner
        let scanTask = self.scanTask

        activeScanSessionID = nil
        self.scanTask = nil

        scanTask?.cancel()

        Task {
            await scanner.cancel()
        }

        if resetScanningState {
            isScanning = false
            isIncrementalScanInProgress = false
            progress = nil
            clearVisibleTree(resetIdentityState: true)
        }
    }

    private func handleLocalScanEvent(_ event: ScanEvent, sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        switch event {
        case .progress(let progress):
            self.progress = progress
        case .partialTree(let subtree):
            mergePartialTree(subtree)
        case .complete(let finalTree):
            completeLocalScan(with: finalTree, sessionID: sessionID)
        }
    }

    private func prepareIncrementalRoot(for directory: URL) {
        stableNodeIDsByPath.removeAll()

        let path = directory.standardizedFileURL.path
        let rootID = stableID(for: path)
        let root = FileNode(
            id: rootID,
            name: Self.displayName(for: directory),
            path: directory.standardizedFileURL,
            isDirectory: true,
            isHidden: directory.lastPathComponent.hasPrefix("."),
            isSymlink: false,
            fileExtension: nil,
            modificationDate: nil,
            size: 0,
            fileCount: 0,
            children: []
        )

        rootNode = root
        currentNode = root
        navigationStack = [root]
        treeMutationRevision += 1
    }

    private func mergePartialTree(_ subtree: FileNodeData) {
        guard let rootNode else { return }

        let parentURL = subtree.url.deletingLastPathComponent().standardizedFileURL
        guard let parent = rootNode.findNode(withPath: parentURL) else { return }

        let subtreePath = standardizedPath(for: subtree.url)
        var children = parent.children ?? []

        if let index = children.firstIndex(where: { standardizedPath(for: $0.path) == subtreePath }) {
            reconcile(children[index], with: subtree)
        } else {
            children.append(makeNode(from: subtree))
        }

        parent.children = children.sorted { $0.size > $1.size }
        rollUpAggregateMetrics(startingAt: parent)
        anchorNavigationToRoot()
        treeMutationRevision += 1
    }

    private func completeLocalScan(with result: FileNodeData, sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        if let rootNode,
           standardizedPath(for: rootNode.path) == standardizedPath(for: result.url) {
            reconcile(rootNode, with: result)
        } else {
            rootNode = makeNode(from: result)
        }

        if let rootNode {
            currentNode = rootNode
            navigationStack = [rootNode]
        }

        resetSearch()
        isScanning = false
        isIncrementalScanInProgress = false
        error = nil
        treeMutationRevision += 1

        finishLocalScan(sessionID: sessionID)
    }

    private func finishCancelledLocalScan(sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        isScanning = false
        isIncrementalScanInProgress = false
        progress = nil
        clearVisibleTree(resetIdentityState: true)
        finishLocalScan(sessionID: sessionID)
    }

    private func finishLocalScan(sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        activeScanSessionID = nil
        scanTask = nil
    }

    private func resetSearch() {
        searchQuery = ""
        searchResults = []
    }

    private func anchorNavigationToRoot() {
        guard isIncrementalScanInProgress, let rootNode else { return }

        currentNode = rootNode
        navigationStack = [rootNode]
        resetSearch()
    }

    private func clearVisibleTree(resetIdentityState: Bool) {
        let hadVisibleTree = rootNode != nil || currentNode != nil || !navigationStack.isEmpty

        rootNode = nil
        currentNode = nil
        navigationStack = []

        if resetIdentityState {
            stableNodeIDsByPath.removeAll()
        }

        if hadVisibleTree {
            treeMutationRevision += 1
        }
    }

    private func standardizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func stableID(for path: String) -> UUID {
        if let id = stableNodeIDsByPath[path] {
            return id
        }

        let id = UUID()
        stableNodeIDsByPath[path] = id
        return id
    }

    private func makeNode(from data: FileNodeData) -> FileNode {
        let standardizedURL = data.url.standardizedFileURL
        let path = standardizedURL.path
        let id = stableID(for: path)
        let children = data.children?.map(makeNode(from:))

        return FileNode(
            id: id,
            name: Self.displayName(for: standardizedURL),
            path: standardizedURL,
            isDirectory: data.isDirectory,
            isHidden: standardizedURL.lastPathComponent.hasPrefix("."),
            isSymlink: data.isSymlink,
            fileExtension: data.isDirectory ? nil : standardizedURL.pathExtension.lowercased(),
            modificationDate: data.modificationDate,
            size: data.size,
            fileCount: data.fileCount,
            children: children
        )
    }

    private func reconcile(_ node: FileNode, with data: FileNodeData) {
        node.size = data.size
        node.fileCount = data.fileCount

        guard data.isDirectory else {
            node.children = nil
            return
        }

        var existingChildrenByPath = Dictionary(
            uniqueKeysWithValues: (node.children ?? []).map { (standardizedPath(for: $0.path), $0) }
        )
        let reconciledChildren = (data.children ?? []).map { childData -> FileNode in
            let childPath = standardizedPath(for: childData.url)

            if let existing = existingChildrenByPath.removeValue(forKey: childPath) {
                reconcile(existing, with: childData)
                return existing
            }

            return makeNode(from: childData)
        }

        node.children = reconciledChildren
    }

    private func rollUpAggregateMetrics(startingAt node: FileNode) {
        guard node.isDirectory else { return }

        let sortedChildren = (node.children ?? []).sorted { $0.size > $1.size }
        node.children = sortedChildren
        node.size = sortedChildren.reduce(0) { $0 + $1.size }
        node.fileCount = sortedChildren.reduce(0) { $0 + $1.fileCount }

        if let parent = findParent(of: node, in: rootNode) {
            rollUpAggregateMetrics(startingAt: parent)
        }
    }

    private func commitNodeRemoval(_ node: FileNode) {
        pruneSearchResults(removing: node)

        if rootNode?.id == node.id {
            rootNode = nil
            currentNode = nil
            navigationStack = []
            searchQuery = ""
            searchResults = []
            treeMutationRevision += 1
            return
        }

        guard let parent = findParent(of: node, in: rootNode) else { return }

        if var children = parent.children {
            children.removeAll { $0.id == node.id }
            parent.children = children
        }

        updateSizes(from: parent)

        if let currentNode, node.containsNode(withID: currentNode.id) {
            navigationStack.removeAll { node.containsNode(withID: $0.id) }

            if navigationStack.isEmpty, let rootNode {
                navigationStack = [rootNode]
            }

            self.currentNode = navigationStack.last ?? parent
            searchQuery = ""
            searchResults = []
        }

        treeMutationRevision += 1
    }

    private func findParent(of node: FileNode, in root: FileNode?) -> FileNode? {
        guard let root else { return nil }

        if root.children?.contains(where: { $0.id == node.id }) == true {
            return root
        }

        for child in root.children ?? [] {
            if let found = findParent(of: node, in: child) {
                return found
            }
        }

        return nil
    }

    private func updateSizes(from node: FileNode) {
        node.size = node.children?.reduce(0) { $0 + $1.size } ?? 0
        node.fileCount = node.children?.reduce(0) { $0 + $1.fileCount } ?? 0

        if let parent = findParent(of: node, in: rootNode) {
            updateSizes(from: parent)
        }
    }

    private func pruneSearchResults(removing node: FileNode) {
        searchResults.removeAll { node.containsNode(withID: $0.id) }
    }
}
