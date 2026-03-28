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
        includeHidden: Bool = false,
        databaseWriter: ScanDatabaseWriter? = nil
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
        activeScanTask = Task(priority: .utility) { [standardizedDirectory, maxDepth, includeHidden, databaseWriter] in
            await self.runScan(
                id: scanID,
                directory: standardizedDirectory,
                maxDepth: maxDepth,
                includeHidden: includeHidden,
                databaseWriter: databaseWriter,
                continuation: continuation
            )
        }

        return stream
    }

    func scanToDatabase(
        directory: URL,
        scanID: UUID,
        maxDepth: Int? = nil,
        includeHidden: Bool = false,
        databaseWriter: ScanDatabaseWriter
    ) -> AsyncStream<ScanEvent> {
        cancelActiveScanIfNeeded()
        resetState()
        let standardizedDirectory = directory.standardizedFileURL
        let (stream, continuation) = AsyncStream.makeStream(
            of: ScanEvent.self,
            bufferingPolicy: .bufferingNewest(Self.streamBufferSize)
        )

        activeScanID = scanID
        activeContinuation = continuation
        activeScanTask = Task(priority: .utility) { [standardizedDirectory, maxDepth, includeHidden, databaseWriter] in
            await self.runScanToDatabase(
                id: scanID,
                directory: standardizedDirectory,
                maxDepth: maxDepth,
                includeHidden: includeHidden,
                databaseWriter: databaseWriter,
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
        databaseWriter: ScanDatabaseWriter?,
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
                databaseWriter: databaseWriter,
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
            try? databaseWriter?.finalize(scanID: id)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func runScanToDatabase(
        id: UUID,
        directory: URL,
        maxDepth: Int?,
        includeHidden: Bool,
        databaseWriter: ScanDatabaseWriter,
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
            try await scanDirectoryToDatabase(
                at: directory,
                depth: 0,
                maxDepth: maxDepth,
                includeHidden: includeHidden,
                modificationDate: nil,
                databaseWriter: databaseWriter,
                continuation: continuation
            )

            try throwIfCancelled()
            try databaseWriter.finalize(scanID: id)
            emit(
                .progress(makeProgress(currentPath: directory.path, isComplete: true)),
                continuation: continuation
            )
            emit(.databaseComplete, continuation: continuation)
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func scanDirectoryToDatabase(
        at directory: URL,
        depth: Int,
        maxDepth: Int?,
        includeHidden: Bool,
        modificationDate: Date?,
        databaseWriter: ScanDatabaseWriter,
        continuation: AsyncStream<ScanEvent>.Continuation
    ) async throws {
        try throwIfCancelled()
        let standardizedDirectory = directory.standardizedFileURL

        if let maxDepth, depth >= maxDepth {
            return
        }

        directoriesScanned += 1
        if let activeScanID {
            var node = LazyFileNode.fromScanEntry(
                url: standardizedDirectory,
                isDirectory: true,
                isSymlink: false,
                fileSize: 0,
                modificationDate: modificationDate,
                scanID: activeScanID
            )
            if depth == 0 {
                node.parentPath = nil
            }
            databaseWriter.add(node)
        }
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
            return
        }

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

                if isDirectory && !isSymlink && !shouldSkipDirectory(standardizedURL, depth: depth + 1) {
                    if isOpaqueDirectory(standardizedURL) {
                        // Fast size-only scan for opaque dirs
                        let (dirSize, dirFileCount) = fastDirectorySize(at: standardizedURL)
                        filesScanned += dirFileCount
                        bytesScanned += dirSize
                        directoriesScanned += 1
                        if let activeScanID {
                            var node = LazyFileNode.fromScanEntry(
                                url: standardizedURL,
                                isDirectory: true,
                                isSymlink: false,
                                fileSize: dirSize,
                                modificationDate: modDate,
                                scanID: activeScanID
                            )
                            node.fileCount = dirFileCount
                            databaseWriter.add(node)
                        }
                        emitProgress(
                            currentPath: Self.displayName(for: standardizedURL),
                            progress: continuation
                        )
                    } else {
                        try await scanDirectoryToDatabase(
                            at: standardizedURL,
                            depth: depth + 1,
                            maxDepth: maxDepth,
                            includeHidden: includeHidden,
                            modificationDate: modDate,
                            databaseWriter: databaseWriter,
                            continuation: continuation
                        )
                    }
                } else {
                    filesScanned += 1
                    bytesScanned += fileSize
                    try await maybeAdaptiveThrottle()
                    if let activeScanID {
                        databaseWriter.add(LazyFileNode.fromScanEntry(
                            url: standardizedURL,
                            isDirectory: isDirectory,
                            isSymlink: isSymlink,
                            fileSize: fileSize,
                            modificationDate: modDate,
                            scanID: activeScanID
                        ))
                    }
                    emitProgress(
                        currentPath: Self.displayName(for: standardizedURL),
                        progress: continuation
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
    }

    private func resetState() {
        isCancelled = false
        filesScanned = 0
        directoriesScanned = 0
        bytesScanned = 0
        startTime = Date()
        lastProgressUpdate = Date()
        visitedRealPaths = []
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
        databaseWriter: ScanDatabaseWriter?,
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
        if let databaseWriter, let activeScanID {
            var node = LazyFileNode.fromScanEntry(
                url: standardizedDirectory,
                isDirectory: true,
                isSymlink: false,
                fileSize: 0,
                modificationDate: modificationDate,
                scanID: activeScanID
            )
            if depth == 0 {
                node.parentPath = nil
            }
            databaseWriter.add(node)
        }
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

                if isDirectory && !isSymlink && !shouldSkipDirectory(standardizedURL, depth: depth + 1) {
                    if isOpaqueDirectory(standardizedURL) {
                        // Fast size-only scan — don't recurse into deep dirs
                        let (dirSize, dirFileCount) = fastDirectorySize(at: standardizedURL)
                        filesScanned += dirFileCount
                        bytesScanned += dirSize
                        directoriesScanned += 1
                        child = FileNodeData(
                            url: standardizedURL,
                            isDirectory: true,
                            isSymlink: false,
                            size: dirSize,
                            modificationDate: modDate,
                            fileCount: dirFileCount,
                            children: []
                        )
                        emitProgress(
                            currentPath: Self.displayName(for: standardizedURL),
                            progress: continuation
                        )
                    } else {
                        child = try await scanDirectory(
                            at: standardizedURL,
                            depth: depth + 1,
                            maxDepth: maxDepth,
                            includeHidden: includeHidden,
                            modificationDate: modDate,
                            directorySize: fileSize,
                            databaseWriter: databaseWriter,
                            continuation: continuation
                        )
                    }
                } else {
                    filesScanned += 1
                    bytesScanned += fileSize
                    try await maybeAdaptiveThrottle()
                    if let databaseWriter, let activeScanID {
                        databaseWriter.add(LazyFileNode.fromScanEntry(
                            url: standardizedURL,
                            isDirectory: isDirectory,
                            isSymlink: isSymlink,
                            fileSize: fileSize,
                            modificationDate: modDate,
                            scanID: activeScanID
                        ))
                    }
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

                if depth <= 1 {
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

    /// Directories that should ALWAYS be skipped — virtual filesystems
    /// and system internals that cause loops or are useless to analyze.
    private static let alwaysSkipNames: Set<String> = [
        ".Spotlight-V100",
        ".fseventsd",
        ".MobileBackups",
        ".MobileBackups.trash",
        ".DocumentRevisions-V100",
        ".Trashes",
        ".vol",
        ".file",
    ]

    /// Directories to treat as opaque — their total size is counted but
    /// children are NOT recursed into. These contain thousands of small
    /// files with deep nesting that stall the scanner.
    private static let opaqueDirectoryNames: Set<String> = [
        "node_modules",
        ".pnpm",
        "Pods",
        ".build",
        ".git",
        "DerivedData",
        ".cache",
        "__pycache__",
        ".tox",
        "vendor",       // Go/PHP/Ruby
    ]

    /// Full paths to skip — firmlinks, virtual mounts, and volumes that
    /// would cause the scanner to loop or double-count.
    private static let skipPaths: Set<String> = [
        "/dev",
        "/proc",
        "/Volumes",
        "/System/Volumes/Data",      // firmlink to data volume (prevents double-scan)
        "/System/Volumes/Preboot",
        "/System/Volumes/Recovery",
        "/System/Volumes/VM",
        "/System/Volumes/Update",
        "/private/var/db",
        "/private/var/folders",
        "/private/var/run",
        "/private/var/vm",
        "/cores",
    ]

    /// Tracks visited real paths to prevent symlink/firmlink loops.
    private var visitedRealPaths: Set<String> = []

    private func shouldSkipDirectory(_ url: URL, depth: Int) -> Bool {
        let path = url.path

        // Always skip known problematic directory names
        let name = url.lastPathComponent
        if Self.alwaysSkipNames.contains(name) {
            return true
        }

        // Skip known full paths
        if Self.skipPaths.contains(path) {
            return true
        }

        // Resolve real path to detect firmlink/symlink loops
        let realPath = (path as NSString).resolvingSymlinksInPath
        if visitedRealPaths.contains(realPath) {
            return true
        }
        visitedRealPaths.insert(realPath)

        return false
    }

    /// Returns true if this directory should be scanned for total size
    /// only, without recursing into individual children.
    private func isOpaqueDirectory(_ url: URL) -> Bool {
        Self.opaqueDirectoryNames.contains(url.lastPathComponent)
    }

    /// Fast size-only scan using FileManager.enumerator — counts total
    /// bytes and file count without building a tree.
    private func fastDirectorySize(at url: URL) -> (size: UInt64, fileCount: Int) {
        var totalSize: UInt64 = 0
        var fileCount = 0

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return (0, 0)
        }

        for case let fileURL as URL in enumerator {
            guard !isCancelled else { break }
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
               !(values.isDirectory ?? false) {
                totalSize += UInt64(values.fileSize ?? 0)
                fileCount += 1
            }
        }

        return (totalSize, fileCount)
    }
}
