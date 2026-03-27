import Foundation
import GRDB

struct LazyFileNode: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "lazyFileNode"

    // Primary key
    var path: String

    // Core properties
    var name: String
    var size: UInt64
    var isDirectory: Bool
    var fileCount: Int
    var parentPath: String?
    var modificationDate: Date?
    var fileExtension: String?
    var isSymlink: Bool
    var isHidden: Bool

    // Scan association
    var scanID: UUID

    // Identifiable
    var id: String { path }

    // Computed (reuse existing utilities)
    var category: FileCategory { FileCategory.categorize(fileExtension) }
    var formattedSize: String { SizeFormatter.format(size) }

    // MARK: - Hashable

    static func == (lhs: LazyFileNode, rhs: LazyFileNode) -> Bool {
        lhs.path == rhs.path
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

// MARK: - Adapter: LazyFileNode → FileNode

extension LazyFileNode {
    /// Materializes a FileNode subtree from the database.
    /// Loads children lazily to the specified depth.
    func toFileNode(provider: LazyFileNodeProvider, maxDepth: Int = 6, currentDepth: Int = 0) throws -> FileNode {
        let node = FileNode(
            url: URL(fileURLWithPath: path),
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            size: size,
            modificationDate: modificationDate
        )
        node.fileCount = fileCount

        if isDirectory && currentDepth < maxDepth {
            let children = try provider.children(of: path, limit: 1000, offset: 0)
            node.children = try children.map {
                try $0.toFileNode(provider: provider, maxDepth: maxDepth, currentDepth: currentDepth + 1)
            }
        }

        return node
    }
}
