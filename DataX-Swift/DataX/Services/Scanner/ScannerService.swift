import Foundation

actor ScannerService {
    private static let progressFileInterval = 100
    private static let progressUpdateInterval: TimeInterval = 0.1
    private static let traversalYieldInterval = 128
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    private var isCancelled = false
    private var filesScanned = 0
    private var directoriesScanned = 0
    private var bytesScanned: UInt64 = 0
    private var startTime = Date()
    private var lastProgressUpdate = Date()

    func scan(
        directory: URL,
        maxDepth: Int? = nil,
        includeHidden: Bool = false,
        progress: AsyncStream<ScanProgress>.Continuation
    ) async throws -> FileNodeData {
        resetState()
        progress.yield(makeProgress(
            currentPath: Self.displayName(for: directory),
            isComplete: false
        ))

        defer {
            progress.finish()
        }

        let root = try await scanDirectory(
            at: directory,
            depth: 0,
            maxDepth: maxDepth,
            includeHidden: includeHidden,
            modificationDate: nil,
            directorySize: 0,
            progress: progress
        )

        try throwIfCancelled()
        progress.yield(makeProgress(currentPath: directory.path, isComplete: true))
        return root
    }

    func cancel() {
        isCancelled = true
    }

    private func resetState() {
        isCancelled = false
        filesScanned = 0
        directoriesScanned = 0
        bytesScanned = 0
        startTime = Date()
        lastProgressUpdate = Date()
    }

    private func throwIfCancelled() throws {
        if isCancelled || Task.isCancelled {
            isCancelled = true
            throw CancellationError()
        }
    }

    private func emitProgress(
        currentPath: String,
        progress: AsyncStream<ScanProgress>.Continuation
    ) {
        let now = Date()
        let shouldEmit = now.timeIntervalSince(lastProgressUpdate) >= Self.progressUpdateInterval
            || (filesScanned > 0 && filesScanned.isMultiple(of: Self.progressFileInterval))

        guard shouldEmit else { return }

        lastProgressUpdate = now
        progress.yield(makeProgress(currentPath: currentPath, isComplete: false))
    }

    private func makeProgress(currentPath: String, isComplete: Bool) -> ScanProgress {
        ScanProgress(
            filesScanned: filesScanned,
            directoriesScanned: directoriesScanned,
            bytesScanned: bytesScanned,
            currentPath: currentPath,
            startTime: startTime,
            isComplete: isComplete
        )
    }

    private func scanDirectory(
        at directory: URL,
        depth: Int,
        maxDepth: Int?,
        includeHidden: Bool,
        modificationDate: Date?,
        directorySize: UInt64,
        progress: AsyncStream<ScanProgress>.Continuation
    ) async throws -> FileNodeData {
        try throwIfCancelled()

        if let maxDepth, depth >= maxDepth {
            return FileNodeData(
                url: directory,
                isDirectory: true,
                isSymlink: false,
                size: directorySize,
                modificationDate: modificationDate,
                fileCount: 0,
                children: []
            )
        }

        directoriesScanned += 1
        emitProgress(
            currentPath: Self.displayName(for: directory),
            progress: progress
        )
        try await maybeYieldTraversalControl()

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: options
            )
        } catch {
            return FileNodeData(
                url: directory,
                isDirectory: true,
                isSymlink: false,
                size: directorySize,
                modificationDate: modificationDate,
                fileCount: 0,
                children: []
            )
        }

        var children: [FileNodeData] = []

        for url in contents {
            try throwIfCancelled()
            try await maybeYieldTraversalControl()

            do {
                let resourceValues = try url.resourceValues(forKeys: Self.resourceKeys)

                let isDirectory = resourceValues.isDirectory ?? false
                let isSymlink = resourceValues.isSymbolicLink ?? false
                let fileSize = UInt64(resourceValues.fileSize ?? 0)
                let modDate = resourceValues.contentModificationDate

                let child: FileNodeData

                if isDirectory && !isSymlink {
                    child = try await scanDirectory(
                        at: url,
                        depth: depth + 1,
                        maxDepth: maxDepth,
                        includeHidden: includeHidden,
                        modificationDate: modDate,
                        directorySize: fileSize,
                        progress: progress
                    )
                } else {
                    filesScanned += 1
                    bytesScanned += fileSize
                    child = FileNodeData(
                        url: url,
                        isDirectory: isDirectory,
                        isSymlink: isSymlink,
                        size: fileSize,
                        modificationDate: modDate,
                        fileCount: 1,
                        children: nil
                    )
                    emitProgress(
                        currentPath: Self.displayName(for: url),
                        progress: progress
                    )
                }

                children.append(child)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }

        let sortedChildren = children.sorted { $0.size > $1.size }
        let aggregateSize = sortedChildren.reduce(0) { $0 + $1.size }
        let aggregateFileCount = sortedChildren.reduce(0) { $0 + $1.fileCount }

        return FileNodeData(
            url: directory,
            isDirectory: true,
            isSymlink: false,
            size: aggregateSize,
            modificationDate: modificationDate,
            fileCount: aggregateFileCount,
            children: sortedChildren
        )
    }

    private func maybeYieldTraversalControl() async throws {
        let visitedEntries = filesScanned + directoriesScanned
        guard visitedEntries > 0, visitedEntries.isMultiple(of: Self.traversalYieldInterval) else {
            return
        }

        await Task.yield()
        try throwIfCancelled()
    }

    private static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}
