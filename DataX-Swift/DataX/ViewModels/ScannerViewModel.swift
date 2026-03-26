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
    var progress: ScanProgress?
    var diskInfo: DiskInfo?
    var error: Error?
    var searchQuery = ""
    var searchResults: [FileNode] = []
    var treeMutationRevision = 0

    // MARK: - Private

    @ObservationIgnored private var scanner = ScannerService()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var activeScanSessionID: UUID?

    // MARK: - Computed Properties

    var canNavigateBack: Bool {
        navigationStack.count > 1
    }

    var currentPath: String {
        currentNode?.path.path ?? ""
    }

    var breadcrumbs: [FileNode] {
        navigationStack
    }

    var displayedChildren: [FileNode]? {
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
        let directoryName = Self.displayName(for: directory)
        let scanner = ScannerService()

        self.scanner = scanner
        activeScanSessionID = sessionID
        isScanning = true
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

        // Get disk info (simplified method that won't hang)
        diskInfo = try? DiskInfo.forPath(directory)

        var progressContinuation: AsyncStream<ScanProgress>.Continuation!
        let progressStream = AsyncStream<ScanProgress>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            progressContinuation = continuation
        }

        let progressTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for await update in progressStream {
                guard self.activeScanSessionID == sessionID else { continue }
                self.progress = update
            }
        }
        self.progressTask = progressTask

        scanTask = Task { [weak self, scanner] in
            guard let self else {
                progressContinuation.finish()
                return
            }

            do {
                let result = try await scanner.scan(
                    directory: directory,
                    progress: progressContinuation
                )
                await progressTask.value
                self.completeLocalScan(with: result, sessionID: sessionID)
            } catch is CancellationError {
                await progressTask.value
                self.finishCancelledLocalScan(sessionID: sessionID)
            } catch {
                await progressTask.value
                self.finishFailedLocalScan(error, sessionID: sessionID)
            }
        }
    }

    func cancelScan() {
        cancelActiveLocalScan(resetScanningState: true)
    }

    func navigateTo(_ node: FileNode) {
        guard node.isDirectory else { return }

        currentNode = node
        searchQuery = ""
        searchResults = []

        // Check if we're navigating to a node already in the stack
        if let index = navigationStack.firstIndex(where: { $0.id == node.id }) {
            navigationStack = Array(navigationStack.prefix(through: index))
        } else {
            navigationStack.append(node)
        }
    }

    func navigateBack() {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        currentNode = navigationStack.last
        searchQuery = ""
        searchResults = []
    }

    func navigateToRoot() {
        guard let root = rootNode else { return }
        currentNode = root
        navigationStack = [root]
        searchQuery = ""
        searchResults = []
    }

    func navigateToBreadcrumb(at index: Int) {
        guard index < navigationStack.count else { return }
        let node = navigationStack[index]
        currentNode = node
        navigationStack = Array(navigationStack.prefix(through: index))
        searchQuery = ""
        searchResults = []
    }

    // MARK: - Search

    func performSearch(_ query: String) {
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
        isScanning = true
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
        error = nil
    }

    func failRemoteScan(with error: Error) {
        self.error = error
        isScanning = false
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
        let progressTask = self.progressTask

        activeScanSessionID = nil
        self.scanTask = nil
        self.progressTask = nil

        scanTask?.cancel()
        progressTask?.cancel()

        Task {
            await scanner.cancel()
        }

        if resetScanningState {
            isScanning = false
            progress = nil
        }
    }

    private func completeLocalScan(with result: FileNodeData, sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        let root = result.toFileNode()
        rootNode = root
        currentNode = root
        navigationStack = [root]
        isScanning = false
        error = nil

        finishLocalScan(sessionID: sessionID)
    }

    private func finishCancelledLocalScan(sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        isScanning = false
        progress = nil
        finishLocalScan(sessionID: sessionID)
    }

    private func finishFailedLocalScan(_ error: Error, sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        self.error = error
        isScanning = false
        progress = nil
        finishLocalScan(sessionID: sessionID)
    }

    private func finishLocalScan(sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        activeScanSessionID = nil
        scanTask = nil
        progressTask = nil
    }

    private func resetSearch() {
        searchQuery = ""
        searchResults = []
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
