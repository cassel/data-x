import Foundation

actor ScannerService {
    private static let progressFileInterval = 100
    private static let progressUpdateInterval: TimeInterval = 0.1
    private static let traversalYieldInterval = 128
    private static let adaptiveQoSThreshold = 100_000
    private static let adaptiveSleepInterval = 5_000
    private static let streamBufferSize = 100
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
    private var activeScanID: UUID?
    private var activeScanTask: Task<Void, Never>?
    private var activeContinuation: AsyncStream<ScanEvent>.Continuation?

    func scan(
        directory: URL,
        maxDepth: Int? = nil,
        includeHidden: Bool = false
    ) -> AsyncStream<ScanEvent> {
        cancelActiveScanIfNeeded()
        resetState()
        let scanID = UUID()
        let standardizedDirectory = directory.standardizedFileURL
        let (stream, continuation) = AsyncStream.makeStream(
            of: ScanEvent.self,
            bufferingPolicy: .bufferingNewest(Self.streamBufferSize)
        )

        activeScanID = scanID
        activeContinuation = continuation
        activeScanTask = Task(priority: .utility) { [standardizedDirectory, maxDepth, includeHidden] in
            await self.runScan(
                id: scanID,
                directory: standardizedDirectory,
                maxDepth: maxDepth,
                includeHidden: includeHidden,
                continuation: continuation
            )
        }

        return stream
    }

    func cancel() {
        isCancelled = true
        activeScanID = nil
        activeScanTask?.cancel()
        activeScanTask = nil
        activeContinuation?.finish()
        activeContinuation = nil
    }

    private func cancelActiveScanIfNeeded() {
        activeScanID = nil
        activeScanTask?.cancel()
        activeScanTask = nil
        activeContinuation?.finish()
        activeContinuation = nil
    }

    private func runScan(
        id: UUID,
        directory: URL,
        maxDepth: Int?,
        includeHidden: Bool,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async {
        defer {
            continuation.finish()

            if activeScanID == id {
                activeScanID = nil
                activeScanTask = nil
                activeContinuation = nil
            }
        }

        emit(
            .progress(
                makeProgress(
                    currentPath: Self.displayName(for: directory),
                    isComplete: false
                )
            ),
            continuation: continuation
        )

        do {
            let root = try await scanDirectory(
                at: directory,
                depth: 0,
                maxDepth: maxDepth,
                includeHidden: includeHidden,
                modificationDate: nil,
                directorySize: 0,
                continuation: continuation
            )

            try throwIfCancelled()
            emit(
                .progress(makeProgress(currentPath: directory.path, isComplete: true)),
                continuation: continuation
            )
            // .complete is the last event emitted — .bufferingNewest drops oldest,
            // so the newest event is never dropped even when the buffer is full.
            emit(.complete(root), continuation: continuation)
        } catch is CancellationError {
            return
        } catch {
            return
        }
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
        progress: AsyncStream<ScanEvent>.Continuation
    ) {
        let now = Date()
        let shouldEmit = now.timeIntervalSince(lastProgressUpdate) >= Self.progressUpdateInterval
            || (filesScanned > 0 && filesScanned.isMultiple(of: Self.progressFileInterval))

        guard shouldEmit else { return }

        lastProgressUpdate = now
        emit(
            .progress(makeProgress(currentPath: currentPath, isComplete: false)),
            continuation: progress
        )
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

    private func emit(
        _ event: ScanEvent,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) {
        switch continuation.yield(event) {
        case .terminated:
            isCancelled = true
        case .dropped, .enqueued:
            break
        @unknown default:
            break
        }
    }

    private func scanDirectory(
        at directory: URL,
        depth: Int,
        maxDepth: Int?,
        includeHidden: Bool,
        modificationDate: Date?,
        directorySize: UInt64,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async throws -> FileNodeData {
        try throwIfCancelled()
        let standardizedDirectory = directory.standardizedFileURL

        if let maxDepth, depth >= maxDepth {
            return FileNodeData(
                url: standardizedDirectory,
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
            currentPath: Self.displayName(for: standardizedDirectory),
            progress: continuation
        )
        try await maybeYieldTraversalControl()

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: standardizedDirectory,
                includingPropertiesForKeys: Array(Self.resourceKeys),
                options: options
            )
        } catch {
            return FileNodeData(
                url: standardizedDirectory,
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
                let standardizedURL = url.standardizedFileURL
                let resourceValues = try standardizedURL.resourceValues(forKeys: Self.resourceKeys)

                let isDirectory = resourceValues.isDirectory ?? false
                let isSymlink = resourceValues.isSymbolicLink ?? false
                let fileSize = UInt64(resourceValues.fileSize ?? 0)
                let modDate = resourceValues.contentModificationDate

                let child: FileNodeData

                if isDirectory && !isSymlink {
                    child = try await scanDirectory(
                        at: standardizedURL,
                        depth: depth + 1,
                        maxDepth: maxDepth,
                        includeHidden: includeHidden,
                        modificationDate: modDate,
                        directorySize: fileSize,
                        continuation: continuation
                    )
                } else {
                    filesScanned += 1
                    bytesScanned += fileSize
                    try await maybeAdaptiveThrottle()
                    child = FileNodeData(
                        url: standardizedURL,
                        isDirectory: isDirectory,
                        isSymlink: isSymlink,
                        size: fileSize,
                        modificationDate: modDate,
                        fileCount: 1,
                        children: nil
                    )
                    emitProgress(
                        currentPath: Self.displayName(for: standardizedURL),
                        progress: continuation
                    )
                }

                children.append(child)

                if depth == 0 {
                    emit(.partialTree(child), continuation: continuation)
                }
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
            url: standardizedDirectory,
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

    private func maybeAdaptiveThrottle() async throws {
        guard filesScanned >= Self.adaptiveQoSThreshold,
              filesScanned.isMultiple(of: Self.adaptiveSleepInterval) else {
            return
        }
        try await Task.sleep(for: .milliseconds(1))
        try throwIfCancelled()
    }

    private static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}
