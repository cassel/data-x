import XCTest
@testable import DataX

@MainActor
final class ScannerViewModelDeletionTests: XCTestCase {
    func testCommitMoveToTrashRemovesNodeUpdatesAncestorsAndPrunesSearchResults() {
        let viewModel = ScannerViewModel()
        let target = makeFile(
            "/root/folder/remove.txt",
            size: 30,
            modificationDate: Date(timeIntervalSince1970: 0)
        )
        let keep = makeFile(
            "/root/folder/keep.txt",
            size: 70,
            modificationDate: Date()
        )
        let folder = makeDirectory("/root/folder", children: [target, keep])
        let root = makeDirectory("/root", children: [folder])

        viewModel.rootNode = root
        viewModel.currentNode = folder
        viewModel.navigationStack = [root, folder]
        viewModel.searchQuery = "txt"
        viewModel.searchResults = [target, keep]
        viewModel.refreshInsightRankings()

        XCTAssertEqual(viewModel.insights.oldFiles?.totalCount, 1)

        viewModel.commitMoveToTrash(target)

        XCTAssertEqual(folder.children?.map(\.id), [keep.id])
        XCTAssertEqual(folder.size, 70)
        XCTAssertEqual(folder.fileCount, 1)
        XCTAssertEqual(root.size, 70)
        XCTAssertEqual(root.fileCount, 1)
        XCTAssertEqual(viewModel.currentNode?.id, folder.id)
        XCTAssertEqual(viewModel.navigationStack.map(\.id), [root.id, folder.id])
        XCTAssertEqual(viewModel.searchResults.map(\.id), [keep.id])
        XCTAssertEqual(viewModel.insights.topFiles.map(\.id), [keep.id])
        XCTAssertEqual(viewModel.insights.topDirectories.map(\.id), [folder.id])
        XCTAssertEqual(viewModel.insights.oldFiles?.totalCount, 0)
        XCTAssertEqual(viewModel.treeMutationRevision, 1)
    }

    func testCommitMoveToTrashNavigatesToParentWhenCurrentNodeIsRemoved() {
        let viewModel = ScannerViewModel()
        let child = makeFile("/root/folder/child.dat", size: 15)
        let folder = makeDirectory("/root/folder", children: [child])
        let sibling = makeFile("/root/sibling.mov", size: 25)
        let root = makeDirectory("/root", children: [folder, sibling])

        viewModel.rootNode = root
        viewModel.currentNode = folder
        viewModel.navigationStack = [root, folder]

        viewModel.commitMoveToTrash(folder)

        XCTAssertEqual(root.children?.map(\.id), [sibling.id])
        XCTAssertEqual(root.size, 25)
        XCTAssertEqual(root.fileCount, 1)
        XCTAssertEqual(viewModel.currentNode?.id, root.id)
        XCTAssertEqual(viewModel.navigationStack.map(\.id), [root.id])
        XCTAssertEqual(viewModel.treeMutationRevision, 1)
    }

    func testMakeTrashUndoRegistrationCapturesOriginalParentAndIndex() {
        let viewModel = ScannerViewModel()
        let keep = makeFile("/root/folder/keep.txt", size: 10)
        let target = makeFile("/root/folder/remove.txt", size: 30)
        let sibling = makeFile("/root/folder/after.txt", size: 50)
        let folder = makeDirectory("/root/folder", children: [keep, target, sibling])
        let root = makeDirectory("/root", children: [folder])

        viewModel.rootNode = root
        viewModel.currentNode = folder
        viewModel.navigationStack = [root, folder]

        let registration = viewModel.makeTrashUndoRegistration(
            for: target,
            trashedItemURL: URL(fileURLWithPath: "/mock/.Trash/remove.txt")
        )

        XCTAssertEqual(registration?.originalItemURL, target.path.standardizedFileURL)
        XCTAssertEqual(registration?.trashedItemURL, URL(fileURLWithPath: "/mock/.Trash/remove.txt").standardizedFileURL)
        XCTAssertEqual(registration?.removedNode.id, target.id)
        XCTAssertEqual(registration?.originalParentPath, folder.path.standardizedFileURL.path)
        XCTAssertEqual(registration?.originalChildIndex, 1)
        XCTAssertEqual(registration?.rootPath, root.path.standardizedFileURL.path)
    }

    func testConfirmMoveToTrashRegistersUndoAndUndoRestoresTreeMetrics() {
        let operations = RecordingFileOperations()
        let viewModel = ScannerViewModel(fileOperations: operations.client)
        let target = makeFile("/root/folder/remove.txt", size: 30)
        let keep = makeFile("/root/folder/keep.txt", size: 70)
        let folder = makeDirectory("/root/folder", children: [target, keep])
        let root = makeDirectory("/root", children: [folder])
        let undoManager = UndoManager()

        viewModel.rootNode = root
        viewModel.currentNode = folder
        viewModel.navigationStack = [root, folder]
        viewModel.requestMoveToTrash(target)

        let removedNode = viewModel.confirmPendingTrash(undoManager: undoManager)

        XCTAssertEqual(removedNode?.id, target.id)
        XCTAssertEqual(operations.moveRequests, [target.path.standardizedFileURL])
        XCTAssertEqual(folder.children?.map(\.id), [keep.id])
        XCTAssertEqual(folder.size, 70)
        XCTAssertEqual(folder.fileCount, 1)
        XCTAssertEqual(root.size, 70)
        XCTAssertEqual(root.fileCount, 1)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()

        XCTAssertEqual(
            operations.restoreRequests,
            [RecordedRestore(
                trashedURL: operations.trashedItemURL,
                originalURL: target.path.standardizedFileURL
            )]
        )
        XCTAssertEqual(folder.children?.map(\.id), [target.id, keep.id])
        XCTAssertEqual(folder.size, 100)
        XCTAssertEqual(folder.fileCount, 2)
        XCTAssertEqual(root.size, 100)
        XCTAssertEqual(root.fileCount, 2)
    }

    func testUndoAfterTreeSessionChangeRestoresFilesystemButDoesNotMutateLaterTree() {
        let operations = RecordingFileOperations()
        let viewModel = ScannerViewModel(fileOperations: operations.client)
        let target = makeFile("/root/folder/remove.txt", size: 30)
        let keep = makeFile("/root/folder/keep.txt", size: 70)
        let folder = makeDirectory("/root/folder", children: [target, keep])
        let root = makeDirectory("/root", children: [folder])
        let replacement = makeFile("/new-root/fresh.txt", size: 99)
        let replacementRoot = makeDirectory("/new-root", children: [replacement])
        let undoManager = UndoManager()

        viewModel.rootNode = root
        viewModel.currentNode = folder
        viewModel.navigationStack = [root, folder]
        viewModel.requestMoveToTrash(target)
        _ = viewModel.confirmPendingTrash(undoManager: undoManager)

        viewModel.completeRemoteScan(with: replacementRoot)
        undoManager.undo()

        XCTAssertEqual(
            operations.restoreRequests,
            [RecordedRestore(
                trashedURL: operations.trashedItemURL,
                originalURL: target.path.standardizedFileURL
            )]
        )
        XCTAssertEqual(viewModel.rootNode?.id, replacementRoot.id)
        XCTAssertEqual(replacementRoot.children?.map(\.id), [replacement.id])
        XCTAssertNil(replacementRoot.findNode(withPath: target.path))
        XCTAssertNotNil(viewModel.error)
    }

    func testCancelPendingTrashRequestDoesNotRegisterUndoOrMutateTree() {
        let operations = RecordingFileOperations()
        let viewModel = ScannerViewModel(fileOperations: operations.client)
        let target = makeFile("/root/folder/remove.txt", size: 30)
        let keep = makeFile("/root/folder/keep.txt", size: 70)
        let folder = makeDirectory("/root/folder", children: [target, keep])
        let root = makeDirectory("/root", children: [folder])
        let undoManager = UndoManager()

        viewModel.rootNode = root
        viewModel.currentNode = folder
        viewModel.navigationStack = [root, folder]
        viewModel.requestMoveToTrash(target)
        viewModel.cancelPendingTrashRequest()

        XCTAssertNil(viewModel.pendingTrashRequest)
        XCTAssertEqual(operations.moveRequests, [])
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertEqual(folder.children?.map(\.id), [target.id, keep.id])
        XCTAssertEqual(root.size, 100)
        XCTAssertEqual(root.fileCount, 2)
    }

    private func makeDirectory(_ path: String, children: [FileNode]) -> FileNode {
        let node = FileNode(url: URL(fileURLWithPath: path), isDirectory: true)
        node.children = children
        node.size = children.reduce(0) { $0 + $1.size }
        node.fileCount = children.reduce(0) { $0 + $1.fileCount }
        return node
    }

    private func makeFile(_ path: String, size: UInt64, modificationDate: Date? = nil) -> FileNode {
        FileNode(
            url: URL(fileURLWithPath: path),
            isDirectory: false,
            size: size,
            modificationDate: modificationDate
        )
    }
}

private final class RecordingFileOperations {
    let trashedItemURL = URL(fileURLWithPath: "/mock/.Trash/remove.txt")
    private(set) var moveRequests: [URL] = []
    private(set) var restoreRequests: [RecordedRestore] = []

    var client: FileOperationsClient {
        FileOperationsClient(
            moveToTrash: { [weak self] url in
                guard let self else {
                    throw FileOperationsService.FileOperationError.moveToTrashFailed(url)
                }

                let standardizedURL = url.standardizedFileURL
                self.moveRequests.append(standardizedURL)
                return FileOperationsService.TrashResult(
                    originalItemURL: standardizedURL,
                    trashedItemURL: self.trashedItemURL
                )
            },
            delete: { _ in },
            restoreFromTrash: { [weak self] trashedURL, originalURL in
                self?.restoreRequests.append(
                    RecordedRestore(
                        trashedURL: trashedURL.standardizedFileURL,
                        originalURL: originalURL.standardizedFileURL
                    )
                )
            }
        )
    }
}

private struct RecordedRestore: Equatable {
    let trashedURL: URL
    let originalURL: URL
}
