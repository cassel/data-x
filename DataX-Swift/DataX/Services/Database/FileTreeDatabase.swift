import Foundation
import GRDB

// MARK: - LazyFileNodeProvider Protocol

protocol LazyFileNodeProvider {
    func root(scanID: UUID) throws -> LazyFileNode?
    func children(of parentPath: String, limit: Int, offset: Int) throws -> [LazyFileNode]
    func childrenCount(of parentPath: String) throws -> Int
}

// MARK: - FileTreeDatabase

final class FileTreeDatabase: @unchecked Sendable {
    private let dbWriter: any DatabaseWriter

    /// Creates a database at the specified file path with WAL mode.
    init(path: String) throws {
        let dbPool = try DatabasePool(path: path)
        self.dbWriter = dbPool
        try migrator.migrate(dbPool)
    }

    /// Creates an in-memory database (for tests).
    init() throws {
        let dbQueue = try DatabaseQueue(path: ":memory:")
        self.dbWriter = dbQueue
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "lazyFileNode") { t in
                t.primaryKey("path", .text)
                t.column("name", .text).notNull()
                t.column("size", .integer).notNull().defaults(to: 0)
                t.column("isDirectory", .boolean).notNull().defaults(to: false)
                t.column("fileCount", .integer).notNull().defaults(to: 0)
                t.column("parentPath", .text)
                t.column("modificationDate", .double)
                t.column("fileExtension", .text)
                t.column("isSymlink", .boolean).notNull().defaults(to: false)
                t.column("isHidden", .boolean).notNull().defaults(to: false)
                t.column("scanID", .text).notNull()
            }
            try db.create(index: "idx_parentPath", on: "lazyFileNode", columns: ["parentPath"])
            try db.create(index: "idx_parentPath_size", on: "lazyFileNode", columns: ["parentPath", "size"])
            try db.create(index: "idx_scanID", on: "lazyFileNode", columns: ["scanID"])
        }
        return migrator
    }

    // MARK: - CRUD Operations

    func insert(_ node: LazyFileNode) throws {
        try dbWriter.write { db in
            try node.insert(db)
        }
    }

    func insertBatch(_ nodes: [LazyFileNode]) throws {
        try dbWriter.write { db in
            for node in nodes {
                try node.insert(db)
            }
        }
    }

    func fetchByPath(_ path: String) throws -> LazyFileNode? {
        try dbWriter.read { db in
            try LazyFileNode.fetchOne(db, key: path)
        }
    }

    func deleteAll(scanID: UUID) throws {
        _ = try dbWriter.write { db in
            try LazyFileNode
                .filter(Column("scanID") == scanID)
                .deleteAll(db)
        }
    }

    func fetchChildren(
        of parentPath: String,
        limit: Int = 1000,
        offset: Int = 0,
        sortedBySizeDesc: Bool = true
    ) throws -> [LazyFileNode] {
        try dbWriter.read { db in
            var request = LazyFileNode
                .filter(Column("parentPath") == parentPath)

            if sortedBySizeDesc {
                request = request.order(Column("size").desc)
            }

            return try request
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }
}

// MARK: - LazyFileNodeProvider Conformance

extension FileTreeDatabase: LazyFileNodeProvider {
    func root(scanID: UUID) throws -> LazyFileNode? {
        try dbWriter.read { db in
            try LazyFileNode
                .filter(Column("scanID") == scanID)
                .filter(Column("parentPath") == nil)
                .fetchOne(db)
        }
    }

    func children(of parentPath: String, limit: Int = 1000, offset: Int = 0) throws -> [LazyFileNode] {
        try fetchChildren(of: parentPath, limit: limit, offset: offset)
    }

    func childrenCount(of parentPath: String) throws -> Int {
        try dbWriter.read { db in
            try LazyFileNode
                .filter(Column("parentPath") == parentPath)
                .fetchCount(db)
        }
    }
}

// MARK: - Default Database Location

extension FileTreeDatabase {
    static func defaultPath() throws -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("DataX", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        return dbDir.appendingPathComponent("filetree.sqlite").path
    }
}
