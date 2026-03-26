import Foundation
import SwiftUI

@Observable
final class FileNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: URL
    let isDirectory: Bool
    let isHidden: Bool
    let isSymlink: Bool
    let fileExtension: String?
    let modificationDate: Date?

    var size: UInt64
    var fileCount: Int
    var children: [FileNode]?

    // Computed properties
    var category: FileCategory {
        FileCategory.categorize(fileExtension)
    }

    var formattedSize: String {
        SizeFormatter.format(size)
    }

    var sortedChildren: [FileNode]? {
        children?.sorted { $0.size > $1.size }
    }

    init(
        url: URL,
        isDirectory: Bool,
        isSymlink: Bool = false,
        size: UInt64 = 0,
        modificationDate: Date? = nil
    ) {
        self.id = UUID()
        self.name = url.lastPathComponent
        self.path = url
        self.isDirectory = isDirectory
        self.isHidden = url.lastPathComponent.hasPrefix(".")
        self.isSymlink = isSymlink
        self.fileExtension = isDirectory ? nil : url.pathExtension.lowercased()
        self.modificationDate = modificationDate
        self.size = size
        self.fileCount = isDirectory ? 0 : 1
    }

    init(
        id: UUID,
        name: String,
        path: URL,
        isDirectory: Bool,
        isHidden: Bool,
        isSymlink: Bool,
        fileExtension: String?,
        modificationDate: Date?,
        size: UInt64,
        fileCount: Int,
        children: [FileNode]?
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isSymlink = isSymlink
        self.fileExtension = fileExtension
        self.modificationDate = modificationDate
        self.size = size
        self.fileCount = fileCount
        self.children = children
    }

    // MARK: - Hashable

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Tree Operations

    func findNode(withPath targetPath: URL) -> FileNode? {
        if path == targetPath { return self }
        guard let children else { return nil }
        for child in children {
            if let found = child.findNode(withPath: targetPath) {
                return found
            }
        }
        return nil
    }

    func containsNode(withID targetID: UUID) -> Bool {
        if id == targetID {
            return true
        }

        return children?.contains { $0.containsNode(withID: targetID) } ?? false
    }

    func clonedSubtree(removingNodeWithID targetID: UUID) -> FileNode? {
        guard id != targetID else { return nil }

        let clonedChildren = children?.compactMap { $0.clonedSubtree(removingNodeWithID: targetID) }
        let rolledUpSize = clonedChildren?.reduce(0) { $0 + $1.size } ?? 0
        let rolledUpFileCount = clonedChildren?.reduce(0) { $0 + $1.fileCount } ?? 0

        return FileNode(
            id: id,
            name: name,
            path: path,
            isDirectory: isDirectory,
            isHidden: isHidden,
            isSymlink: isSymlink,
            fileExtension: fileExtension,
            modificationDate: modificationDate,
            size: isDirectory ? (clonedChildren != nil ? rolledUpSize : size) : size,
            fileCount: isDirectory ? (clonedChildren != nil ? rolledUpFileCount : fileCount) : fileCount,
            children: clonedChildren
        )
    }

    func allFiles() -> [FileNode] {
        var files: [FileNode] = []
        collectFiles(into: &files)
        return files
    }

    private func collectFiles(into array: inout [FileNode]) {
        if !isDirectory {
            array.append(self)
        }
        children?.forEach { $0.collectFiles(into: &array) }
    }
}

// MARK: - Sendable wrapper for async operations

struct FileNodeData: Sendable {
    let url: URL
    let isDirectory: Bool
    let isSymlink: Bool
    let size: UInt64
    let modificationDate: Date?
    let children: [FileNodeData]?

    func toFileNode() -> FileNode {
        let node = FileNode(
            url: url,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            size: size,
            modificationDate: modificationDate
        )
        node.children = children?.map { $0.toFileNode() }
        node.fileCount = children?.reduce(0) { $0 + $1.toFileNode().fileCount } ?? (isDirectory ? 0 : 1)
        return node
    }
}
