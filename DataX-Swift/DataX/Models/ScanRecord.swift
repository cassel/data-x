import Foundation
import SwiftData

@Model
final class ScanRecord {
    var rootPath: String
    var timestamp: Date
    var totalSize: UInt64
    var duration: TimeInterval
    var fileCount: Int
    var dirCount: Int
    var topChildrenJSON: String

    init(
        rootPath: String,
        timestamp: Date,
        totalSize: UInt64,
        duration: TimeInterval,
        fileCount: Int,
        dirCount: Int,
        topChildrenJSON: String
    ) {
        self.rootPath = rootPath
        self.timestamp = timestamp
        self.totalSize = totalSize
        self.duration = duration
        self.fileCount = fileCount
        self.dirCount = dirCount
        self.topChildrenJSON = topChildrenJSON
    }

    func decodedTopChildren() throws -> [TopChildSnapshot] {
        try Self.decodeTopChildren(from: topChildrenJSON)
    }

    static func snapshots(from root: FileNode) -> [TopChildSnapshot] {
        (root.children ?? []).map { child in
            TopChildSnapshot(
                name: child.name,
                size: child.size,
                isDirectory: child.isDirectory
            )
        }
    }

    static func encodeTopChildren(from root: FileNode) throws -> String {
        try encodeTopChildren(snapshots(from: root))
    }

    static func decodeTopChildren(from json: String) throws -> [TopChildSnapshot] {
        let data = Data(json.utf8)
        return try makeDecoder().decode([TopChildSnapshot].self, from: data)
    }

    private static func encodeTopChildren(_ snapshots: [TopChildSnapshot]) throws -> String {
        let data = try makeEncoder().encode(snapshots)
        return String(decoding: data, as: UTF8.self)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}

extension ScanRecord {
    struct TopChildSnapshot: Codable, Hashable, Sendable {
        let name: String
        let size: UInt64
        let isDirectory: Bool
    }
}
