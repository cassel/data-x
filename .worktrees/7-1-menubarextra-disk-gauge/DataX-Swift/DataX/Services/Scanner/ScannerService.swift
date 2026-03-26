import Foundation

final class ScannerService {
    private var isCancelled = false
    private var filesScanned = 0
    private var directoriesScanned = 0
    private var bytesScanned: UInt64 = 0
    private var startTime = Date()
    private var lastProgressUpdate = Date()

    private let queue = DispatchQueue(label: "com.datax.scanner", qos: .userInitiated)

    func scan(
        directory: URL,
        maxDepth: Int? = nil,
        includeHidden: Bool = false,
        progress: @escaping (ScanProgress) -> Void,
        completion: @escaping (Result<FileNode, Error>) -> Void
    ) {
        // Reset state
        isCancelled = false
        filesScanned = 0
        directoriesScanned = 0
        bytesScanned = 0
        startTime = Date()
        lastProgressUpdate = Date()

        // Send initial progress on main thread
        DispatchQueue.main.async {
            progress(ScanProgress(
                filesScanned: 0,
                directoriesScanned: 0,
                bytesScanned: 0,
                currentPath: directory.lastPathComponent,
                startTime: self.startTime,
                isComplete: false
            ))
        }

        // Run scan on background queue
        queue.async { [weak self] in
            guard let self = self else { return }

            let root = FileNode(url: directory, isDirectory: true)

            self.scanDirectorySync(
                node: root,
                depth: 0,
                maxDepth: maxDepth,
                includeHidden: includeHidden,
                progress: progress
            )

            // Send final progress and result on main thread
            DispatchQueue.main.async {
                let finalProgress = ScanProgress(
                    filesScanned: self.filesScanned,
                    directoriesScanned: self.directoriesScanned,
                    bytesScanned: self.bytesScanned,
                    currentPath: directory.path,
                    startTime: self.startTime,
                    isComplete: true
                )
                progress(finalProgress)
                completion(.success(root))
            }
        }
    }

    func cancel() {
        isCancelled = true
    }

    private func emitProgress(currentPath: String, progress: @escaping (ScanProgress) -> Void) {
        let now = Date()
        let shouldEmit = now.timeIntervalSince(lastProgressUpdate) >= 0.1 || filesScanned % 100 == 0

        if shouldEmit {
            lastProgressUpdate = now
            let currentProgress = ScanProgress(
                filesScanned: filesScanned,
                directoriesScanned: directoriesScanned,
                bytesScanned: bytesScanned,
                currentPath: currentPath,
                startTime: startTime,
                isComplete: false
            )
            DispatchQueue.main.async {
                progress(currentProgress)
            }
        }
    }

    private func scanDirectorySync(
        node: FileNode,
        depth: Int,
        maxDepth: Int?,
        includeHidden: Bool,
        progress: @escaping (ScanProgress) -> Void
    ) {
        guard !isCancelled else { return }

        if let maxDepth, depth >= maxDepth {
            return
        }

        directoriesScanned += 1
        emitProgress(currentPath: node.name, progress: progress)

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: node.path,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: options
            )
        } catch {
            return
        }

        var children: [FileNode] = []

        for url in contents {
            guard !isCancelled else { break }

            do {
                let resourceValues = try url.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ])

                let isDirectory = resourceValues.isDirectory ?? false
                let isSymlink = resourceValues.isSymbolicLink ?? false
                let fileSize = UInt64(resourceValues.fileSize ?? 0)
                let modDate = resourceValues.contentModificationDate

                let child = FileNode(
                    url: url,
                    isDirectory: isDirectory,
                    isSymlink: isSymlink,
                    size: fileSize,
                    modificationDate: modDate
                )

                if isDirectory && !isSymlink {
                    scanDirectorySync(
                        node: child,
                        depth: depth + 1,
                        maxDepth: maxDepth,
                        includeHidden: includeHidden,
                        progress: progress
                    )
                } else {
                    filesScanned += 1
                    bytesScanned += fileSize
                    child.fileCount = 1
                    emitProgress(currentPath: child.name, progress: progress)
                }

                children.append(child)
            } catch {
                continue
            }
        }

        node.children = children.sorted { $0.size > $1.size }
        node.size = children.reduce(0) { $0 + $1.size }
        node.fileCount = children.reduce(0) { $0 + $1.fileCount }
    }
}
