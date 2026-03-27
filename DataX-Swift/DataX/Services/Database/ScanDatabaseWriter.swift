import Foundation
import GRDB

final class ScanDatabaseWriter: @unchecked Sendable {
    private let database: FileTreeDatabase
    private var buffer: [LazyFileNode] = []
    private let queue = DispatchQueue(label: "com.datax.scan-db-writer")
    private var flushError: Error?
    private static let batchSize = 1000

    init(database: FileTreeDatabase) {
        self.database = database
    }

    func add(_ node: LazyFileNode) {
        queue.sync {
            buffer.append(node)
            if buffer.count >= Self.batchSize {
                flushUnsafe()
            }
        }
    }

    func flush() throws {
        try queue.sync {
            flushUnsafe()
            if let error = flushError {
                flushError = nil
                throw error
            }
        }
    }

    private func flushUnsafe() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        do {
            try database.insertBatch(batch)
        } catch {
            flushError = error
        }
    }

    func beginScan(scanID: UUID, rootPath: String) throws {
        try database.deleteAllNodes()
    }

    func finalize(scanID: UUID) throws {
        try flush()
        try database.aggregateDirectorySizes(scanID: scanID)
    }
}
