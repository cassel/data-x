import CryptoKit
import Foundation

struct DuplicateCandidate: Sendable, Equatable {
    let path: URL
    let size: UInt64
    let modificationDate: Date?
    let isSymlink: Bool

    var standardizedPath: String {
        path.standardizedFileURL.path
    }

    @MainActor
    static func makeList(from root: FileNode) -> [Self] {
        root.allFiles()
            .map {
                DuplicateCandidate(
                    path: $0.path.standardizedFileURL,
                    size: $0.size,
                    modificationDate: $0.modificationDate,
                    isSymlink: $0.isSymlink
                )
            }
            .filter { !$0.isSymlink && $0.size >= DuplicateDetector.minimumFileSize }
            .sorted(by: DuplicateDetector.compareCandidates)
    }
}

struct DuplicateFile: Sendable, Equatable, Identifiable {
    let path: String
    let size: UInt64
    let modificationDate: Date?

    var id: String { path }

    var name: String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    var modificationLabel: String {
        guard let modificationDate else {
            return "Modified date unavailable"
        }

        return "Modified \(modificationDate.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct DuplicateGroup: Sendable, Equatable, Identifiable {
    let size: UInt64
    let files: [DuplicateFile]

    var id: String {
        files.map(\.path).joined(separator: "|")
    }

    var copyCount: Int {
        files.count
    }

    var totalSize: UInt64 {
        size * UInt64(copyCount)
    }

    var reclaimableSpace: UInt64 {
        guard copyCount > 1 else { return 0 }
        return size * UInt64(copyCount - 1)
    }

    var canonicalFileName: String {
        files.first?.name ?? "Duplicate"
    }

    var canonicalPath: String {
        files.first?.path ?? ""
    }

    var suggestedOriginalPath: String {
        files.first?.path ?? ""
    }

    var titleText: String {
        "\(copyCount) \(copyCount == 1 ? "copy" : "copies") of \(canonicalFileName) (\(SizeFormatter.format(totalSize)))"
    }

    var reclaimableText: String {
        "Reclaim \(SizeFormatter.format(reclaimableSpace))"
    }

    func isSuggestedOriginal(_ file: DuplicateFile) -> Bool {
        file.path == suggestedOriginalPath
    }
}

struct DuplicateReport: Sendable, Equatable {
    let groups: [DuplicateGroup]
    let unreadablePaths: [String]

    var hasResults: Bool {
        !groups.isEmpty
    }

    var totalCopies: Int {
        groups.reduce(0) { $0 + $1.copyCount }
    }

    var totalDuplicateCopies: Int {
        groups.reduce(0) { $0 + max(0, $1.copyCount - 1) }
    }

    var totalReclaimableSpace: UInt64 {
        groups.reduce(0) { $0 + $1.reclaimableSpace }
    }

    var warningMessage: String? {
        guard !unreadablePaths.isEmpty else { return nil }

        let count = unreadablePaths.count
        let noun = count == 1 ? "file" : "files"
        let verb = count == 1 ? "was" : "were"
        return "\(count) \(noun) \(verb) unreadable during hashing and excluded from the duplicate results."
    }

    var summaryText: String {
        "\(groups.count) \(groups.count == 1 ? "group" : "groups") • \(totalDuplicateCopies) extra \(totalDuplicateCopies == 1 ? "copy" : "copies") • \(SizeFormatter.format(totalReclaimableSpace)) reclaimable"
    }

    var emptyStateText: String {
        "No confirmed duplicates were found in this scan."
    }
}

enum DuplicateReportState: Equatable {
    case idle
    case loading
    case failed(String)
    case loaded(DuplicateReport)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }

        return false
    }

    var primaryActionTitle: String {
        switch self {
        case .loaded, .failed:
            return "Refresh"
        case .idle, .loading:
            return "Scan for Duplicates"
        }
    }

    var shouldForceRefresh: Bool {
        switch self {
        case .loaded, .failed:
            return true
        case .idle, .loading:
            return false
        }
    }

    var report: DuplicateReport? {
        guard case .loaded(let report) = self else { return nil }
        return report
    }
}

protocol DuplicateDetecting: Sendable {
    func detectDuplicates(in candidates: [DuplicateCandidate]) async throws -> DuplicateReport
}

actor DuplicateDetector: DuplicateDetecting {
    static let minimumFileSize: UInt64 = 1_024

    func detectDuplicates(in candidates: [DuplicateCandidate]) async throws -> DuplicateReport {
        let filteredCandidates = candidates
            .filter { !$0.isSymlink && $0.size >= Self.minimumFileSize }
            .sorted(by: Self.compareCandidates)

        guard filteredCandidates.count > 1 else {
            return DuplicateReport(groups: [], unreadablePaths: [])
        }

        var unreadablePaths: Set<String> = []
        var confirmedGroups: [DuplicateGroup] = []

        for sizeGroup in Self.makeSizeGroups(from: filteredCandidates) {
            try Task.checkCancellation()

            var partialGroups: [String: [DuplicateCandidate]] = [:]

            for candidate in sizeGroup {
                try Task.checkCancellation()

                do {
                    let partialDigest = try DuplicateHasher.partialDigest(
                        for: candidate.path,
                        expectedSize: candidate.size
                    )
                    partialGroups[partialDigest, default: []].append(candidate)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    unreadablePaths.insert(candidate.standardizedPath)
                }
            }

            for partialGroup in partialGroups.values where partialGroup.count > 1 {
                try Task.checkCancellation()

                var fullGroups: [String: [DuplicateFile]] = [:]

                for candidate in partialGroup.sorted(by: Self.compareCandidates) {
                    try Task.checkCancellation()

                    do {
                        let fullDigest = try DuplicateHasher.fullDigest(
                            for: candidate.path,
                            expectedSize: candidate.size
                        )
                        let file = DuplicateFile(
                            path: candidate.standardizedPath,
                            size: candidate.size,
                            modificationDate: candidate.modificationDate
                        )
                        fullGroups[fullDigest, default: []].append(file)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        unreadablePaths.insert(candidate.standardizedPath)
                    }
                }

                for files in fullGroups.values where files.count > 1 {
                    confirmedGroups.append(
                        DuplicateGroup(
                            size: files.first?.size ?? 0,
                            files: files.sorted(by: Self.compareFiles)
                        )
                    )
                }
            }
        }

        return DuplicateReport(
            groups: confirmedGroups.sorted(by: Self.compareGroups),
            unreadablePaths: unreadablePaths.sorted()
        )
    }

    nonisolated static func compareCandidates(_ lhs: DuplicateCandidate, _ rhs: DuplicateCandidate) -> Bool {
        if lhs.size != rhs.size {
            return lhs.size > rhs.size
        }

        return lhs.standardizedPath < rhs.standardizedPath
    }

    private nonisolated static func compareFiles(_ lhs: DuplicateFile, _ rhs: DuplicateFile) -> Bool {
        switch (lhs.modificationDate, rhs.modificationDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.path < rhs.path
        }
    }

    private nonisolated static func compareGroups(_ lhs: DuplicateGroup, _ rhs: DuplicateGroup) -> Bool {
        if lhs.reclaimableSpace != rhs.reclaimableSpace {
            return lhs.reclaimableSpace > rhs.reclaimableSpace
        }

        if lhs.canonicalFileName != rhs.canonicalFileName {
            return lhs.canonicalFileName < rhs.canonicalFileName
        }

        return lhs.canonicalPath < rhs.canonicalPath
    }

    private nonisolated static func makeSizeGroups(from candidates: [DuplicateCandidate]) -> [[DuplicateCandidate]] {
        var groups: [[DuplicateCandidate]] = []
        var currentGroup: [DuplicateCandidate] = []
        var currentSize: UInt64?

        for candidate in candidates {
            if currentSize == candidate.size {
                currentGroup.append(candidate)
                continue
            }

            if currentGroup.count > 1 {
                groups.append(currentGroup)
            }

            currentGroup = [candidate]
            currentSize = candidate.size
        }

        if currentGroup.count > 1 {
            groups.append(currentGroup)
        }

        return groups
    }
}

enum DuplicateHasher {
    static let edgeWindowSize = 4 * 1_024
    private static let smallFileThreshold = edgeWindowSize * 2
    private static let fullHashChunkSize = 64 * 1_024

    static func partialDigest(for url: URL, expectedSize: UInt64) throws -> String {
        if expectedSize <= UInt64(smallFileThreshold) {
            return try fullDigest(for: url, expectedSize: expectedSize)
        }

        let handle = try makeValidatedHandle(for: url, expectedSize: expectedSize)
        defer { try? handle.close() }

        let prefix = try handle.read(upToCount: edgeWindowSize) ?? Data()
        guard prefix.count == edgeWindowSize else {
            throw DuplicateHashingError.metadataChanged(url)
        }

        try handle.seek(toOffset: expectedSize - UInt64(edgeWindowSize))

        let suffix = try handle.read(upToCount: edgeWindowSize) ?? Data()
        guard suffix.count == edgeWindowSize else {
            throw DuplicateHashingError.metadataChanged(url)
        }

        return sha256Hex(of: prefix + suffix)
    }

    static func fullDigest(for url: URL, expectedSize: UInt64) throws -> String {
        let handle = try makeValidatedHandle(for: url, expectedSize: expectedSize)
        defer { try? handle.close() }

        var hasher = SHA256()
        var totalBytesRead: UInt64 = 0

        while true {
            let chunk = try handle.read(upToCount: fullHashChunkSize) ?? Data()

            if chunk.isEmpty {
                break
            }

            totalBytesRead += UInt64(chunk.count)
            hasher.update(data: chunk)
        }

        guard totalBytesRead == expectedSize else {
            throw DuplicateHashingError.metadataChanged(url)
        }

        return sha256Hex(of: hasher.finalize())
    }

    private static func makeValidatedHandle(for url: URL, expectedSize: UInt64) throws -> FileHandle {
        let standardizedURL = url.standardizedFileURL
        let actualSize = try currentSize(of: standardizedURL)

        guard actualSize == expectedSize else {
            throw DuplicateHashingError.metadataChanged(standardizedURL)
        }

        return try FileHandle(forReadingFrom: standardizedURL)
    }

    private static func currentSize(of url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? UInt64 ?? 0
    }

    private static func sha256Hex<C: DataProtocol>(of data: C) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(of digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

private enum DuplicateHashingError: LocalizedError {
    case metadataChanged(URL)

    var errorDescription: String? {
        switch self {
        case .metadataChanged(let url):
            return "File changed while hashing: \(url.lastPathComponent)"
        }
    }
}
