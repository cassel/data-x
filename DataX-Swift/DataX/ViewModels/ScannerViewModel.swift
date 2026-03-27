import Foundation
import OSLog
import SwiftData
import SwiftUI

struct OldFileInsights: Equatable {
    struct DirectoryGroup: Equatable, Identifiable {
        let directoryPath: String
        let files: [FileNode]

        var id: String { directoryPath }

        var totalSize: UInt64 {
            files.reduce(0) { $0 + $1.size }
        }

        var fileCount: Int {
            files.count
        }

        var displayName: String {
            let name = URL(fileURLWithPath: directoryPath).lastPathComponent
            return name.isEmpty ? directoryPath : name
        }

        var fileCountText: String {
            "\(fileCount) \(fileCount == 1 ? "file" : "files")"
        }
    }

    let cutoffDate: Date
    let directoryGroups: [DirectoryGroup]

    var totalCount: Int {
        directoryGroups.reduce(0) { $0 + $1.fileCount }
    }

    var totalSize: UInt64 {
        directoryGroups.reduce(0) { $0 + $1.totalSize }
    }

    var hasResults: Bool {
        !directoryGroups.isEmpty
    }

    var summaryText: String {
        "\(totalCount) \(totalCount == 1 ? "file" : "files") (\(SizeFormatter.format(totalSize))) not modified since \(cutoffDate.formatted(date: .abbreviated, time: .omitted))"
    }

    var emptyStateText: String {
        "No files older than \(cutoffDate.formatted(date: .abbreviated, time: .omitted))."
    }
}

struct ScanInsights: Equatable {
    let topFiles: [FileNode]
    let topDirectories: [FileNode]
    let oldFiles: OldFileInsights?

    static let empty = Self(topFiles: [], topDirectories: [], oldFiles: nil)

    static func make(
        from root: FileNode,
        topFilesLimit: Int = 10,
        topDirectoryLimit: Int = 5,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        var topFiles: [FileNode] = []
        var topDirectories: [FileNode] = []
        var oldFilesByDirectoryPath: [String: [FileNode]] = [:]
        let cutoffDate = FilterViewModel.DatePreset.older.cutoffDate(
            relativeTo: referenceDate,
            calendar: calendar
        )

        func rankKey(for node: FileNode) -> (UInt64, String) {
            (node.size, node.path.standardizedFileURL.path)
        }

        func insert(_ node: FileNode, into rankings: inout [FileNode], limit: Int) {
            guard limit > 0 else { return }

            rankings.append(node)
            rankings.sort { lhs, rhs in
                let lhsKey = rankKey(for: lhs)
                let rhsKey = rankKey(for: rhs)

                if lhsKey.0 != rhsKey.0 {
                    return lhsKey.0 > rhsKey.0
                }

                return lhsKey.1 < rhsKey.1
            }

            if rankings.count > limit {
                rankings.removeLast(rankings.count - limit)
            }
        }

        func walk(_ node: FileNode, isRoot: Bool) {
            if node.isDirectory {
                if !isRoot {
                    insert(node, into: &topDirectories, limit: topDirectoryLimit)
                }

                for child in node.children ?? [] {
                    walk(child, isRoot: false)
                }
            } else {
                insert(node, into: &topFiles, limit: topFilesLimit)

                if let cutoffDate, node.isOldFile(cutoffDate: cutoffDate) {
                    let directoryPath = node.path.deletingLastPathComponent().standardizedFileURL.path
                    oldFilesByDirectoryPath[directoryPath, default: []].append(node)
                }
            }
        }

        walk(root, isRoot: true)
        let oldFiles = cutoffDate.map { cutoffDate in
            OldFileInsights(
                cutoffDate: cutoffDate,
                directoryGroups: oldFilesByDirectoryPath
                    .map { directoryPath, files in
                        let sortedFiles = files.sorted { lhs, rhs in
                            let lhsKey = rankKey(for: lhs)
                            let rhsKey = rankKey(for: rhs)

                            if lhsKey.0 != rhsKey.0 {
                                return lhsKey.0 > rhsKey.0
                            }

                            return lhsKey.1 < rhsKey.1
                        }

                        return OldFileInsights.DirectoryGroup(
                            directoryPath: directoryPath,
                            files: sortedFiles
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.totalSize != rhs.totalSize {
                            return lhs.totalSize > rhs.totalSize
                        }

                        return lhs.directoryPath < rhs.directoryPath
                    }
            )
        }

        return Self(topFiles: topFiles, topDirectories: topDirectories, oldFiles: oldFiles)
    }
}

struct TrashConfirmationRequest: Identifiable, Equatable {
    let id = UUID()
    let node: FileNode
    let treeSessionID: UUID

    var itemKind: String {
        node.isDirectory ? "Folder" : "File"
    }

    var confirmButtonTitle: String {
        "Move \(itemKind) to Trash"
    }

    var confirmationMessage: String {
        [
            "\(itemKind): \(node.name)",
            "Size: \(SizeFormatter.format(node.size))",
            "Path: \(node.path.standardizedFileURL.path)"
        ]
        .joined(separator: "\n")
    }
}

struct TrashUndoRegistration {
    let originalItemURL: URL
    let trashedItemURL: URL
    let removedNode: FileNode
    let originalParentPath: String?
    let originalChildIndex: Int
    let treeSessionID: UUID
    let rootPath: String?
}

private enum TrashTreeRestoreResult {
    case restored
    case skipped
}

private enum TrashUndoWarning: LocalizedError {
    case restoredOutsideCurrentScan(URL)

    var errorDescription: String? {
        switch self {
        case .restoredOutsideCurrentScan(let url):
            return "'\(url.lastPathComponent)' was restored to its original location, but the active scan changed. Refresh to see the restored item."
        }
    }
}

struct GrowthAlertBannerState: Equatable, Identifiable {
    let path: String
    let growthBytes: Int64
    let previousScanDate: Date

    var id: String {
        "\(path)-\(previousScanDate.timeIntervalSinceReferenceDate)-\(growthBytes)"
    }

    var formattedGrowthText: String {
        SizeFormatter.format(UInt64(growthBytes))
    }

    var message: String {
        "\(path) grew \(formattedGrowthText) since \(previousScanDate.formatted(date: .abbreviated, time: .omitted))"
    }
}

enum ScanGrowthAlertEvaluator {
    static let absoluteGrowthThresholdBytes: UInt64 = 5_000_000_000
    private static let percentageGrowthThreshold = 0.2

    static func growthAlertState(from recentRecords: [ScanRecord]) -> GrowthAlertBannerState? {
        guard recentRecords.count >= 2 else { return nil }

        let sortedRecords = recentRecords.sorted(by: newestFirst)
        let current = sortedRecords[0]
        let previous = sortedRecords[1]

        guard current.rootPath == previous.rootPath else { return nil }

        let deltaBytes = ScanHistoryMath.deltaBytes(
            current: current.totalSize,
            previous: previous.totalSize
        )

        guard deltaBytes > 0 else { return nil }

        let positiveGrowthBytes = UInt64(deltaBytes)
        let exceedsAbsoluteThreshold = positiveGrowthBytes > absoluteGrowthThresholdBytes
        let exceedsPercentageThreshold = if previous.totalSize == 0 {
            false
        } else {
            Double(positiveGrowthBytes) / Double(previous.totalSize) > percentageGrowthThreshold
        }

        guard exceedsAbsoluteThreshold || exceedsPercentageThreshold else { return nil }

        return GrowthAlertBannerState(
            path: current.rootPath,
            growthBytes: deltaBytes,
            previousScanDate: previous.timestamp
        )
    }

    private static func newestFirst(_ lhs: ScanRecord, _ rhs: ScanRecord) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }

        if lhs.totalSize != rhs.totalSize {
            return lhs.totalSize > rhs.totalSize
        }

        return lhs.fileCount > rhs.fileCount
    }
}

@MainActor
@Observable
final class ScannerViewModel {
    private static let scanFailedTitle = "Scan Failed"
    private static let moveToTrashFailedTitle = "Move to Trash Failed"
    private static let undoMoveToTrashFailedTitle = "Undo Move to Trash Failed"
    private static let undoMoveToTrashLimitedTitle = "Undo Move to Trash Limited"
    private static let deleteFailedTitle = "Delete Failed"
    private static let persistenceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DataX",
        category: "ScanHistory"
    )

    // MARK: - State

    var rootNode: FileNode?
    var currentNode: FileNode?
    var navigationStack: [FileNode] = []
    var isScanning = false
    var isIncrementalScanInProgress = false
    var progress: ScanProgress?
    var diskInfo: DiskInfo?
    var error: Error?
    var errorAlertTitle = "Scan Failed"
    var growthAlertBanner: GrowthAlertBannerState?
    var insights = ScanInsights.empty
    var duplicateReportState: DuplicateReportState = .idle
    var pendingTrashRequest: TrashConfirmationRequest?
    var searchQuery = ""
    @ObservationIgnored var searchResults: [FileNode] = []
    var treeMutationRevision = 0

    private static let largeScanDuplicateThreshold = 500_000

    var isLargeScanForDuplicates: Bool {
        rootNode?.fileCount ?? 0 > Self.largeScanDuplicateThreshold
    }

    // MARK: - Private

    @ObservationIgnored private var scanner = ScannerService()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private let duplicateDetector: any DuplicateDetecting
    @ObservationIgnored private let fileOperations: FileOperationsClient
    @ObservationIgnored private var duplicateScanTask: Task<Void, Never>?
    @ObservationIgnored private var activeScanSessionID: UUID?
    @ObservationIgnored private var currentTreeSessionID = UUID()
    @ObservationIgnored private var duplicateReportRevision: Int?
    @ObservationIgnored private var stableNodeIDsByPath: [String: UUID] = [:]
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var growthAlertDismissTask: Task<Void, Never>?
    @ObservationIgnored private var lastLayoutRevisionTime = Date.distantPast
    @ObservationIgnored private var lastProgressUIUpdateTime = Date.distantPast
    @ObservationIgnored private var latestScanProgress: ScanProgress?

    init(
        duplicateDetector: any DuplicateDetecting = DuplicateDetector(),
        fileOperations: FileOperationsClient = .live
    ) {
        self.duplicateDetector = duplicateDetector
        self.fileOperations = fileOperations
    }

    // MARK: - Computed Properties

    var canNavigateBack: Bool {
        !isIncrementalScanInProgress && navigationStack.count > 1
    }

    var currentPath: String {
        currentNode?.path.path ?? ""
    }

    var breadcrumbs: [FileNode] {
        navigationStack
    }

    var displayedChildren: [FileNode]? {
        if isIncrementalScanInProgress {
            return currentNode?.sortedChildren
        }

        if !searchQuery.isEmpty {
            return searchResults
        }

        return currentNode?.sortedChildren
    }

    // MARK: - Actions

    func configurePersistence(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func scan(directory: URL) {
        cancelActiveLocalScan(resetScanningState: false)
        dismissGrowthAlert()
        advanceTreeSession()
        invalidateDuplicateReport()

        let sessionID = UUID()
        let startTime = Date()
        let standardizedDirectory = directory.standardizedFileURL
        let directoryName = Self.displayName(for: standardizedDirectory)
        let scanner = ScannerService()

        self.scanner = scanner
        activeScanSessionID = sessionID
        isScanning = true
        isIncrementalScanInProgress = true
        lastProgressUIUpdateTime = .distantPast
        latestScanProgress = nil
        clearError()
        progress = ScanProgress(
            filesScanned: 0,
            directoriesScanned: 0,
            bytesScanned: 0,
            currentPath: directoryName,
            startTime: startTime,
            isComplete: false
        )
        resetSearch()
        resetInsightRankings()
        diskInfo = try? DiskInfo.forPath(standardizedDirectory)
        prepareIncrementalRoot(for: standardizedDirectory)

        scanTask = Task { [weak self, scanner, standardizedDirectory] in
            guard let self else {
                await scanner.cancel()
                return
            }

            let events = await scanner.scan(directory: standardizedDirectory)
            var didComplete = false

            for await event in events {
                guard !Task.isCancelled else { break }
                guard self.activeScanSessionID == sessionID else { break }

                if case .complete = event {
                    didComplete = true
                }

                self.handleLocalScanEvent(event, sessionID: sessionID)
            }

            guard self.activeScanSessionID == sessionID else { return }
            guard !didComplete else { return }

            self.finishCancelledLocalScan(sessionID: sessionID)
        }
    }

    func cancelScan() {
        if activeScanSessionID != nil {
            cancelActiveLocalScan(resetScanningState: true)
            return
        }

        isScanning = false
        progress = nil
    }

    func navigateTo(_ node: FileNode) {
        guard !isIncrementalScanInProgress, node.isDirectory else { return }

        currentNode = node
        searchQuery = ""
        searchResults = []

        if let index = navigationStack.firstIndex(where: { $0.id == node.id }) {
            navigationStack = Array(navigationStack.prefix(through: index))
        } else {
            navigationStack.append(node)
        }
    }

    func navigateBack() {
        guard !isIncrementalScanInProgress, navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        currentNode = navigationStack.last
        searchQuery = ""
        searchResults = []
    }

    func navigateToRoot() {
        guard !isIncrementalScanInProgress, let root = rootNode else { return }
        currentNode = root
        navigationStack = [root]
        searchQuery = ""
        searchResults = []
    }

    func navigateToBreadcrumb(at index: Int) {
        guard !isIncrementalScanInProgress, index < navigationStack.count else { return }
        let node = navigationStack[index]
        currentNode = node
        navigationStack = Array(navigationStack.prefix(through: index))
        searchQuery = ""
        searchResults = []
    }

    // MARK: - Search

    func performSearch(_ query: String) {
        guard !isIncrementalScanInProgress else {
            resetSearch()
            return
        }

        searchQuery = query

        guard !query.isEmpty, let root = currentNode else {
            searchResults = []
            return
        }

        let lowercasedQuery = query.lowercased()
        var results: [FileNode] = []

        func searchNode(_ node: FileNode) {
            if node.name.lowercased().contains(lowercasedQuery) {
                results.append(node)
            }
            node.children?.forEach { searchNode($0) }
        }

        searchNode(root)
        searchResults = results.sorted { $0.size > $1.size }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
    }

    func refreshInsightRankings() {
        guard !isScanning,
              !isIncrementalScanInProgress,
              let rootNode else {
            insights = .empty
            return
        }

        insights = ScanInsights.make(from: rootNode)
    }

    func scanForDuplicates(forceRefresh: Bool = false) {
        guard !isScanning,
              !isIncrementalScanInProgress,
              let rootNode else {
            invalidateDuplicateReport()
            return
        }

        if case .loading = duplicateReportState {
            return
        }

        let currentRevision = treeMutationRevision

        if !forceRefresh,
           duplicateReportRevision == currentRevision,
           case .loaded = duplicateReportState {
            return
        }

        let candidates = DuplicateCandidate.makeList(from: rootNode)

        if candidates.count < 2 {
            duplicateReportState = .loaded(DuplicateReport(groups: [], unreadablePaths: []))
            duplicateReportRevision = currentRevision
            return
        }

        duplicateScanTask?.cancel()
        duplicateReportState = .loading
        duplicateReportRevision = nil

        let detector = duplicateDetector

        duplicateScanTask = Task.detached(priority: .utility) { [weak self, detector, candidates, currentRevision] in
            do {
                let report = try await detector.detectDuplicates(in: candidates)
                guard !Task.isCancelled else { return }
                await self?.finishDuplicateReport(report, revision: currentRevision)
            } catch is CancellationError {
                return
            } catch {
                await self?.failDuplicateReport(error, revision: currentRevision)
            }
        }
    }

    func invalidateDuplicateReport() {
        duplicateScanTask?.cancel()
        duplicateScanTask = nil
        duplicateReportRevision = nil
        duplicateReportState = .idle
    }

    func node(atPath path: String) -> FileNode? {
        rootNode?.findNode(withPath: URL(fileURLWithPath: path).standardizedFileURL)
    }

    // MARK: - File Operations

    func revealInFinder(_ node: FileNode) {
        FileOperationsService.revealInFinder(node.path)
    }

    func dismissError() {
        clearError()
    }

    func dismissGrowthAlert() {
        growthAlertDismissTask?.cancel()
        growthAlertDismissTask = nil
        growthAlertBanner = nil
    }

    func requestMoveToTrash(_ node: FileNode) {
        clearError()
        pendingTrashRequest = TrashConfirmationRequest(
            node: node,
            treeSessionID: currentTreeSessionID
        )
    }

    func cancelPendingTrashRequest() {
        pendingTrashRequest = nil
    }

    @discardableResult
    func confirmPendingTrash(undoManager: UndoManager?) -> FileNode? {
        guard let request = pendingTrashRequest else { return nil }
        pendingTrashRequest = nil

        guard request.treeSessionID == currentTreeSessionID,
              let node = rootNode?.findNode(withPath: request.node.path.standardizedFileURL) else {
            presentError(
                FileOperationsService.FileOperationError.fileNotFound(request.node.path.standardizedFileURL),
                title: Self.moveToTrashFailedTitle
            )
            return nil
        }

        return performMoveToTrash(node, undoManager: undoManager)
    }

    func commitMoveToTrash(_ node: FileNode) {
        commitNodeRemoval(node)
    }

    func moveToTrash(_ node: FileNode) {
        requestMoveToTrash(node)
    }

    func deleteFile(_ node: FileNode) {
        clearError()

        do {
            try fileOperations.delete(node.path.standardizedFileURL)
            commitNodeRemoval(node)
        } catch {
            presentError(error, title: Self.deleteFailedTitle)
        }
    }

    func openFile(_ node: FileNode) {
        FileOperationsService.openFile(node.path)
    }

    func openInTerminal(_ node: FileNode) {
        FileOperationsService.openInTerminal(node.path)
    }

    func copyPath(_ node: FileNode) {
        FileOperationsService.copyPath(node.path)
    }

    func resetToHomeState() {
        dismissGrowthAlert()
        advanceTreeSession()
        cancelPendingTrashRequest()
        isScanning = false
        isIncrementalScanInProgress = false
        progress = nil
        diskInfo = nil
        resetSearch()
        clearVisibleTree(resetIdentityState: true)
        clearError()
    }

    func beginRemoteScan() {
        cancelActiveLocalScan(resetScanningState: false)
        dismissGrowthAlert()
        advanceTreeSession()
        clearVisibleTree(resetIdentityState: true)
        isScanning = true
        isIncrementalScanInProgress = false
        clearError()
        resetInsightRankings()
        progress = .initial
        resetSearch()
    }

    func updateRemoteProgress(_ newProgress: ScanProgress) {
        progress = newProgress
    }

    func completeRemoteScan(with root: FileNode) {
        advanceTreeSession()
        handleCompletedScan(root)
    }

    func failRemoteScan(with error: Error) {
        presentError(error, title: Self.scanFailedTitle)
        isScanning = false
        isIncrementalScanInProgress = false
        resetInsightRankings()
        invalidateDuplicateReport()
        progress = nil
    }

    // MARK: - Private Helpers

    private static func displayName(for directory: URL) -> String {
        let name = directory.lastPathComponent
        return name.isEmpty ? directory.path : name
    }

    private func cancelActiveLocalScan(resetScanningState: Bool) {
        let scanner = self.scanner
        let scanTask = self.scanTask

        activeScanSessionID = nil
        self.scanTask = nil

        scanTask?.cancel()

        Task {
            await scanner.cancel()
        }

        if resetScanningState {
            advanceTreeSession()
            isScanning = false
            isIncrementalScanInProgress = false
            progress = nil
            clearVisibleTree(resetIdentityState: true)
        }
    }

    private func handleLocalScanEvent(_ event: ScanEvent, sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        switch event {
        case .progress(let progress):
            latestScanProgress = progress
            let now = Date()
            if now.timeIntervalSince(lastProgressUIUpdateTime) >= 0.25 {
                lastProgressUIUpdateTime = now
                self.progress = progress
            }
        case .partialTree(let subtree):
            mergePartialTree(subtree)
        case .complete(let finalTree):
            completeLocalScan(with: finalTree, sessionID: sessionID)
        }
    }

    private func prepareIncrementalRoot(for directory: URL) {
        stableNodeIDsByPath.removeAll()

        let path = directory.standardizedFileURL.path
        let rootID = stableID(for: path)
        let root = FileNode(
            id: rootID,
            name: Self.displayName(for: directory),
            path: directory.standardizedFileURL,
            isDirectory: true,
            isHidden: directory.lastPathComponent.hasPrefix("."),
            isSymlink: false,
            fileExtension: nil,
            modificationDate: nil,
            size: 0,
            fileCount: 0,
            children: []
        )

        rootNode = root
        currentNode = root
        navigationStack = [root]
        treeMutationRevision += 1
    }

    private func mergePartialTree(_ subtree: FileNodeData) {
        guard let rootNode else { return }

        let parentURL = subtree.url.deletingLastPathComponent().standardizedFileURL
        guard let parent = rootNode.findNode(withPath: parentURL) else { return }

        let subtreePath = standardizedPath(for: subtree.url)
        var children = parent.children ?? []

        if let index = children.firstIndex(where: { standardizedPath(for: $0.path) == subtreePath }) {
            reconcile(children[index], with: subtree)
        } else {
            children.append(makeNode(from: subtree))
        }

        parent.children = children
        rollUpAggregateMetrics(startingAt: parent)
        anchorNavigationToRoot()
        let now = Date()
        if now.timeIntervalSince(lastLayoutRevisionTime) >= 0.5 {
            lastLayoutRevisionTime = now
            treeMutationRevision += 1
        }
    }

    func handleCompletedScan(_ root: FileNode, progress: ScanProgress? = nil) {
        if let progress {
            self.progress = progress
        }

        root.sortChildrenBySize()
        rootNode = root
        currentNode = root
        navigationStack = [root]
        resetSearch()
        isScanning = false
        isIncrementalScanInProgress = false
        clearError()
        refreshInsightRankings()
        invalidateDuplicateReport()
        lastLayoutRevisionTime = .distantPast
        lastProgressUIUpdateTime = .distantPast
        treeMutationRevision += 1

        persistCompletedScan(root: root, progress: self.progress)
    }

    func makeScanRecord(
        root: FileNode,
        progress: ScanProgress?,
        timestamp: Date = .now
    ) throws -> ScanRecord {
        let duration = progress.map { max(timestamp.timeIntervalSince($0.startTime), 0) } ?? 0
        let dirCount = if let progress, progress.directoriesScanned > 0 {
            progress.directoriesScanned
        } else {
            directoryCount(in: root)
        }

        return ScanRecord(
            rootPath: root.path.path,
            timestamp: timestamp,
            totalSize: root.size,
            duration: duration,
            fileCount: root.fileCount,
            dirCount: dirCount,
            topChildrenJSON: try ScanRecord.encodeTopChildren(from: root)
        )
    }

    func directoryCount(in root: FileNode) -> Int {
        guard root.isDirectory else { return 0 }

        return 1 + (root.children ?? []).reduce(0) { partialResult, child in
            partialResult + directoryCount(in: child)
        }
    }

    private func completeLocalScan(with result: FileNodeData, sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        if let rootNode,
           standardizedPath(for: rootNode.path) == standardizedPath(for: result.url) {
            reconcile(rootNode, with: result)
        } else {
            rootNode = makeNode(from: result)
        }

        if let latestScanProgress {
            self.progress = latestScanProgress
        }
        latestScanProgress = nil

        if let rootNode {
            handleCompletedScan(rootNode)
        }

        finishLocalScan(sessionID: sessionID)
    }

    private func finishCancelledLocalScan(sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        advanceTreeSession()
        isScanning = false
        isIncrementalScanInProgress = false
        progress = nil
        latestScanProgress = nil
        lastLayoutRevisionTime = .distantPast
        lastProgressUIUpdateTime = .distantPast
        clearVisibleTree(resetIdentityState: true)
        finishLocalScan(sessionID: sessionID)
    }

    private func finishLocalScan(sessionID: UUID) {
        guard activeScanSessionID == sessionID else { return }

        activeScanSessionID = nil
        scanTask = nil
    }

    private func persistCompletedScan(root: FileNode, progress: ScanProgress?) {
        guard let modelContext else { return }

        do {
            let record = try makeScanRecord(root: root, progress: progress)
            modelContext.insert(record)
            try modelContext.save()
            try presentGrowthAlertIfNeeded(afterPersisting: record, in: modelContext)
        } catch {
            Self.persistenceLogger.error(
                "Failed to persist scan history for \(root.path.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func presentGrowthAlertIfNeeded(afterPersisting record: ScanRecord, in modelContext: ModelContext) throws {
        let recentRecords = try recentRecords(for: record.rootPath, limit: 2, in: modelContext)

        guard recentRecords.count == 2,
              recentRecords.first?.persistentModelID == record.persistentModelID,
              let bannerState = ScanGrowthAlertEvaluator.growthAlertState(from: recentRecords) else {
            return
        }

        showGrowthAlert(bannerState)
    }

    private func recentRecords(
        for rootPath: String,
        limit: Int,
        in modelContext: ModelContext
    ) throws -> [ScanRecord] {
        let rootPath = rootPath
        var descriptor = FetchDescriptor<ScanRecord>(
            predicate: #Predicate<ScanRecord> { record in
                record.rootPath == rootPath
            },
            sortBy: [SortDescriptor(\ScanRecord.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func showGrowthAlert(_ bannerState: GrowthAlertBannerState) {
        growthAlertDismissTask?.cancel()
        growthAlertBanner = bannerState

        growthAlertDismissTask = Task { [weak self, bannerID = bannerState.id] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dismissGrowthAlertIfMatching(bannerID)
        }
    }

    private func dismissGrowthAlertIfMatching(_ bannerID: String) {
        guard growthAlertBanner?.id == bannerID else { return }
        growthAlertBanner = nil
        growthAlertDismissTask = nil
    }

    private func resetSearch() {
        if !searchQuery.isEmpty { searchQuery = "" }
        if !searchResults.isEmpty { searchResults = [] }
    }

    private func resetInsightRankings() {
        insights = .empty
    }

    private func anchorNavigationToRoot() {
        guard isIncrementalScanInProgress, let rootNode else { return }
        if currentNode !== rootNode { currentNode = rootNode }
        if navigationStack.count != 1 || navigationStack.first !== rootNode {
            navigationStack = [rootNode]
        }
        resetSearch()
    }

    private func clearVisibleTree(resetIdentityState: Bool) {
        let hadVisibleTree = rootNode != nil || currentNode != nil || !navigationStack.isEmpty

        pendingTrashRequest = nil
        invalidateDuplicateReport()
        rootNode = nil
        currentNode = nil
        navigationStack = []

        if resetIdentityState {
            stableNodeIDsByPath.removeAll()
        }

        if hadVisibleTree {
            treeMutationRevision += 1
        }

        resetInsightRankings()
    }

    func makeTrashUndoRegistration(
        for node: FileNode,
        trashedItemURL: URL
    ) -> TrashUndoRegistration? {
        let standardizedItemURL = node.path.standardizedFileURL
        let standardizedTrashURL = trashedItemURL.standardizedFileURL
        let rootPath = rootNode?.path.standardizedFileURL.path

        if rootNode?.id == node.id {
            return TrashUndoRegistration(
                originalItemURL: standardizedItemURL,
                trashedItemURL: standardizedTrashURL,
                removedNode: node,
                originalParentPath: nil,
                originalChildIndex: 0,
                treeSessionID: currentTreeSessionID,
                rootPath: rootPath
            )
        }

        guard let parent = findParent(of: node, in: rootNode),
              let originalChildIndex = parent.children?.firstIndex(where: { $0.id == node.id }) else {
            return nil
        }

        return TrashUndoRegistration(
            originalItemURL: standardizedItemURL,
            trashedItemURL: standardizedTrashURL,
            removedNode: node,
            originalParentPath: parent.path.standardizedFileURL.path,
            originalChildIndex: originalChildIndex,
            treeSessionID: currentTreeSessionID,
            rootPath: rootPath
        )
    }

    private func performMoveToTrash(_ node: FileNode, undoManager: UndoManager?) -> FileNode? {
        clearError()

        do {
            let trashResult = try fileOperations.moveToTrash(node.path.standardizedFileURL)

            if let registration = makeTrashUndoRegistration(
                for: node,
                trashedItemURL: trashResult.trashedItemURL
            ) {
                registerUndo(registration, undoManager: undoManager)
            }

            commitNodeRemoval(node)
            return node
        } catch {
            presentError(error, title: Self.moveToTrashFailedTitle)
            return nil
        }
    }

    private func registerUndo(_ registration: TrashUndoRegistration, undoManager: UndoManager?) {
        guard let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { target in
            target.undoMoveToTrash(registration, undoManager: undoManager)
        }
        undoManager.setActionName("Move to Trash")
    }

    private func undoMoveToTrash(_ registration: TrashUndoRegistration, undoManager: UndoManager?) {
        clearError()

        do {
            try fileOperations.restoreFromTrash(
                registration.trashedItemURL,
                registration.originalItemURL
            )

            switch restoreNodeInTree(from: registration) {
            case .restored:
                undoManager?.setActionName("Move to Trash")
            case .skipped:
                presentError(
                    TrashUndoWarning.restoredOutsideCurrentScan(registration.originalItemURL),
                    title: Self.undoMoveToTrashLimitedTitle
                )
            }
        } catch {
            presentError(error, title: Self.undoMoveToTrashFailedTitle)
        }
    }

    private func restoreNodeInTree(from registration: TrashUndoRegistration) -> TrashTreeRestoreResult {
        guard registration.treeSessionID == currentTreeSessionID else {
            return .skipped
        }

        if registration.originalParentPath == nil {
            rootNode = registration.removedNode
            currentNode = registration.removedNode
            navigationStack = [registration.removedNode]
            refreshInsightRankings()
            invalidateDuplicateReport()
            treeMutationRevision += 1
            return .restored
        }

        guard let rootNode,
              let originalParentPath = registration.originalParentPath,
              let parent = rootNode.findNode(withPath: URL(fileURLWithPath: originalParentPath).standardizedFileURL) else {
            return .skipped
        }

        var children = parent.children ?? []

        if !children.contains(where: { $0.id == registration.removedNode.id }) {
            let insertionIndex = min(max(registration.originalChildIndex, 0), children.count)
            children.insert(registration.removedNode, at: insertionIndex)
            parent.children = children
            updateSizes(from: parent)
        }

        syncNavigationState(preferredNode: currentNode ?? parent)
        refreshSearchResultsIfNeeded()
        refreshInsightRankings()
        invalidateDuplicateReport()
        treeMutationRevision += 1
        return .restored
    }

    private func refreshSearchResultsIfNeeded() {
        guard !searchQuery.isEmpty else { return }
        performSearch(searchQuery)
    }

    private func syncNavigationState(preferredNode: FileNode?) {
        guard let rootNode else {
            currentNode = nil
            navigationStack = []
            return
        }

        guard let preferredNode,
              rootNode.containsNode(withID: preferredNode.id) else {
            currentNode = rootNode
            navigationStack = [rootNode]
            return
        }

        currentNode = preferredNode
        navigationStack = FileNodePathResolver.path(from: rootNode, to: preferredNode)
    }

    private func clearError() {
        error = nil
        errorAlertTitle = Self.scanFailedTitle
    }

    private func presentError(_ error: Error, title: String) {
        self.error = error
        errorAlertTitle = title
    }

    private func advanceTreeSession() {
        currentTreeSessionID = UUID()
        pendingTrashRequest = nil
    }

    private func standardizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func stableID(for path: String) -> UUID {
        if let id = stableNodeIDsByPath[path] {
            return id
        }

        let id = UUID()
        stableNodeIDsByPath[path] = id
        return id
    }

    private func makeNode(from data: FileNodeData) -> FileNode {
        let standardizedURL = data.url.standardizedFileURL
        let path = standardizedURL.path
        let id = stableID(for: path)
        let children = data.children?.map(makeNode(from:))

        return FileNode(
            id: id,
            name: Self.displayName(for: standardizedURL),
            path: standardizedURL,
            isDirectory: data.isDirectory,
            isHidden: standardizedURL.lastPathComponent.hasPrefix("."),
            isSymlink: data.isSymlink,
            fileExtension: data.isDirectory ? nil : standardizedURL.pathExtension.lowercased(),
            modificationDate: data.modificationDate,
            size: data.size,
            fileCount: data.fileCount,
            children: children
        )
    }

    private func reconcile(_ node: FileNode, with data: FileNodeData) {
        node.size = data.size
        node.fileCount = data.fileCount

        guard data.isDirectory else {
            node.children = nil
            return
        }

        var existingChildrenByPath = Dictionary(
            uniqueKeysWithValues: (node.children ?? []).map { (standardizedPath(for: $0.path), $0) }
        )
        let reconciledChildren = (data.children ?? []).map { childData -> FileNode in
            let childPath = standardizedPath(for: childData.url)

            if let existing = existingChildrenByPath.removeValue(forKey: childPath) {
                reconcile(existing, with: childData)
                return existing
            }

            return makeNode(from: childData)
        }

        node.children = reconciledChildren
    }

    private func rollUpAggregateMetrics(startingAt node: FileNode) {
        guard node.isDirectory else { return }

        let kids = node.children ?? []
        node.size = kids.reduce(0) { $0 + $1.size }
        node.fileCount = kids.reduce(0) { $0 + $1.fileCount }

        if let parent = findParent(of: node, in: rootNode) {
            rollUpAggregateMetrics(startingAt: parent)
        }
    }

    private func commitNodeRemoval(_ node: FileNode) {
        invalidateDuplicateReport()
        pruneSearchResults(removing: node)

        if rootNode?.id == node.id {
            rootNode = nil
            currentNode = nil
            navigationStack = []
            searchQuery = ""
            searchResults = []
            resetInsightRankings()
            treeMutationRevision += 1
            return
        }

        guard let parent = findParent(of: node, in: rootNode) else { return }

        if var children = parent.children {
            children.removeAll { $0.id == node.id }
            parent.children = children
        }

        updateSizes(from: parent)

        if let currentNode, node.containsNode(withID: currentNode.id) {
            navigationStack.removeAll { node.containsNode(withID: $0.id) }

            if navigationStack.isEmpty, let rootNode {
                navigationStack = [rootNode]
            }

            self.currentNode = navigationStack.last ?? parent
            searchQuery = ""
            searchResults = []
        }

        refreshInsightRankings()
        treeMutationRevision += 1
    }

    private func findParent(of node: FileNode, in root: FileNode?) -> FileNode? {
        guard let root else { return nil }

        if root.children?.contains(where: { $0.id == node.id }) == true {
            return root
        }

        for child in root.children ?? [] {
            if let found = findParent(of: node, in: child) {
                return found
            }
        }

        return nil
    }

    private func updateSizes(from node: FileNode) {
        node.size = node.children?.reduce(0) { $0 + $1.size } ?? 0
        node.fileCount = node.children?.reduce(0) { $0 + $1.fileCount } ?? 0

        if let parent = findParent(of: node, in: rootNode) {
            updateSizes(from: parent)
        }
    }

    private func pruneSearchResults(removing node: FileNode) {
        searchResults.removeAll { node.containsNode(withID: $0.id) }
    }

    private func finishDuplicateReport(_ report: DuplicateReport, revision: Int) {
        guard treeMutationRevision == revision,
              !isScanning,
              rootNode != nil else {
            duplicateScanTask = nil
            return
        }

        duplicateReportState = .loaded(report)
        duplicateReportRevision = revision
        duplicateScanTask = nil
    }

    private func failDuplicateReport(_ error: Error, revision: Int) {
        guard treeMutationRevision == revision,
              !isScanning,
              rootNode != nil else {
            duplicateScanTask = nil
            return
        }

        duplicateReportState = .failed("Duplicate scan failed: \(error.localizedDescription)")
        duplicateReportRevision = nil
        duplicateScanTask = nil
    }
}
