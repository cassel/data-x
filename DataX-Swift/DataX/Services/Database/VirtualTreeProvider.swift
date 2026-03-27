import Foundation

/// Sits between `FileTreeDatabase` and the UI, managing which portion of the file tree
/// is materialized as `FileNode` objects in memory. Uses an LRU cache with a configurable
/// node budget (default 50,000) and loads subtrees on demand from the database.
///
/// **Thread Safety:** All cache and database access is serialized on a private serial
/// `DispatchQueue`. Callers may invoke methods from any thread.
final class VirtualTreeProvider: @unchecked Sendable {
    private let database: FileTreeDatabase
    private let scanID: UUID
    private let cache: LRUCache<String, FileNode>
    private let queue = DispatchQueue(label: "com.datax.virtual-tree-provider")

    init(database: FileTreeDatabase, scanID: UUID, nodeBudget: Int = 50_000) {
        self.database = database
        self.scanID = scanID
        self.cache = LRUCache(capacity: nodeBudget)

        cache.onEvict = { _, fileNode in
            fileNode.children = nil
        }
    }

    // MARK: - Public API

    /// Loads the root node and materializes a subtree to the given depth.
    func rootNode(maxDepth: Int = 6) throws -> FileNode? {
        try queue.sync {
            guard let lazyRoot = try database.root(scanID: scanID) else { return nil }
            return try materializeSubtree(from: lazyRoot, maxDepth: maxDepth)
        }
    }

    /// Loads children for a given node from the database and materializes them to the given depth.
    func loadChildren(of node: FileNode, depth: Int = 6) throws {
        try queue.sync {
            let children = try database.fetchChildren(of: node.path.path, limit: 1000)
            node.children = try children.map { lazyChild in
                try materializeSubtree(from: lazyChild, maxDepth: depth, currentDepth: 1)
            }
        }
    }

    /// Preloads one level of children for a path (navigation anticipation).
    func prefetchChildren(of path: String) throws {
        try queue.sync {
            let lazyChildren = try database.fetchChildren(of: path, limit: 1000)
            for child in lazyChildren {
                if cache.get(child.path) == nil {
                    let fileNode = makeFileNode(from: child)
                    cache.set(child.path, value: fileNode)
                }
            }
        }
    }

    // MARK: - Navigation

    /// Returns the cached node for a path, or loads it fresh from the database.
    func nodeForPath(_ path: String) throws -> FileNode? {
        try queue.sync {
            if let cached = cache.get(path) {
                return cached
            }
            guard let lazy = try database.fetchByPath(path) else { return nil }
            let node = makeFileNode(from: lazy)
            cache.set(path, value: node)
            return node
        }
    }

    /// Ensures a node's subtree is loaded to the requested depth.
    /// Walks the tree and loads missing children from the database.
    func ensureDepth(for node: FileNode, depth: Int) throws {
        try queue.sync {
            try ensureDepthRecursive(node: node, remainingDepth: depth)
        }
    }

    /// Current number of nodes in the cache (for diagnostics).
    var nodeCount: Int {
        queue.sync { cache.count }
    }

    // MARK: - Private: Materialization

    private func materializeSubtree(
        from lazyNode: LazyFileNode,
        maxDepth: Int,
        currentDepth: Int = 0
    ) throws -> FileNode {
        // Cache hit: reuse existing FileNode
        if let cached = cache.get(lazyNode.path) {
            return cached
        }

        let fileNode = makeFileNode(from: lazyNode)

        // Load children if within depth budget
        if lazyNode.isDirectory && currentDepth < maxDepth {
            let lazyChildren = try database.fetchChildren(of: lazyNode.path, limit: 1000)
            fileNode.children = try lazyChildren.map { child in
                try materializeSubtree(from: child, maxDepth: maxDepth, currentDepth: currentDepth + 1)
            }
        }
        // else: children remains nil (lazy boundary)

        cache.set(lazyNode.path, value: fileNode)
        return fileNode
    }

    private func makeFileNode(from lazy: LazyFileNode) -> FileNode {
        let node = FileNode(
            url: URL(fileURLWithPath: lazy.path),
            isDirectory: lazy.isDirectory,
            isSymlink: lazy.isSymlink,
            size: lazy.size,
            modificationDate: lazy.modificationDate
        )
        node.fileCount = lazy.fileCount
        return node
    }

    private func ensureDepthRecursive(node: FileNode, remainingDepth: Int) throws {
        guard node.isDirectory, remainingDepth > 0 else { return }

        if node.children == nil {
            let lazyChildren = try database.fetchChildren(of: node.path.path, limit: 1000)
            node.children = try lazyChildren.map { child in
                try materializeSubtree(from: child, maxDepth: remainingDepth - 1, currentDepth: 0)
            }
        } else if let children = node.children {
            for child in children {
                try ensureDepthRecursive(node: child, remainingDepth: remainingDepth - 1)
            }
        }
    }
}
