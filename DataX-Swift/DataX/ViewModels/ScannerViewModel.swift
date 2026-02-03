import Foundation
import SwiftUI

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

    // MARK: - Private

    private let scanner = ScannerService()

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
        isScanning = true
        error = nil
        progress = .initial
        searchQuery = ""
        searchResults = []

        // Get disk info (simplified method that won't hang)
        diskInfo = try? DiskInfo.forPath(directory)

        // Start scan with callbacks
        scanner.scan(
            directory: directory,
            progress: { [weak self] newProgress in
                self?.progress = newProgress
            },
            completion: { [weak self] result in
                switch result {
                case .success(let root):
                    self?.rootNode = root
                    self?.currentNode = root
                    self?.navigationStack = [root]
                    self?.isScanning = false
                case .failure(let error):
                    self?.error = error
                    self?.isScanning = false
                }
            }
        )
    }

    func cancelScan() {
        scanner.cancel()
        isScanning = false
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

    func moveToTrash(_ node: FileNode) {
        do {
            try FileOperationsService.moveToTrash(node.path)
            removeNodeFromTree(node)
        } catch {
            self.error = error
        }
    }

    func deleteFile(_ node: FileNode) {
        do {
            try FileOperationsService.delete(node.path)
            removeNodeFromTree(node)
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

    // MARK: - Private Helpers

    private func removeNodeFromTree(_ node: FileNode) {
        guard let parent = findParent(of: node, in: rootNode) else { return }

        if var children = parent.children {
            children.removeAll { $0.id == node.id }
            parent.children = children

            // Update sizes up the tree
            updateSizes(from: parent)
        }

        // If we removed the current node, navigate to parent
        if currentNode?.id == node.id {
            currentNode = parent
            if let lastIndex = navigationStack.lastIndex(where: { $0.id == node.id }) {
                navigationStack.remove(at: lastIndex)
            }
        }
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
}
