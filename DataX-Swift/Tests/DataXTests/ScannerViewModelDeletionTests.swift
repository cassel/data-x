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
