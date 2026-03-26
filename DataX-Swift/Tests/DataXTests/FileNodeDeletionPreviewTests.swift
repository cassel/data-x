import XCTest
@testable import DataX

final class FileNodeDeletionPreviewTests: XCTestCase {
    func testClonedSubtreeRemovingNestedNodePreservesIdentityAndRecalculatesAncestors() {
        let keep = makeFile("/root/folder/keep.txt", size: 20)
        let remove = makeFile("/root/folder/remove.txt", size: 30)
        let folder = makeDirectory("/root/folder", children: [keep, remove])
        let sibling = makeFile("/root/sibling.mov", size: 50)
        let root = makeDirectory("/root", children: [folder, sibling])

        let preview = root.clonedSubtree(removingNodeWithID: remove.id)

        XCTAssertEqual(preview?.id, root.id)
        XCTAssertFalse(preview === root)
        XCTAssertNil(preview?.findNode(withPath: remove.path))

        let previewFolder = preview?.findNode(withPath: folder.path)
        XCTAssertEqual(previewFolder?.id, folder.id)
        XCTAssertFalse(previewFolder === folder)
        XCTAssertEqual(previewFolder?.children?.map(\.id), [keep.id])
        XCTAssertEqual(previewFolder?.size, 20)
        XCTAssertEqual(previewFolder?.fileCount, 1)
        XCTAssertEqual(preview?.size, 70)
        XCTAssertEqual(preview?.fileCount, 2)
    }

    func testClonedSubtreeReturnsNilWhenRemovingRootNode() {
        let child = makeFile("/root/child.dat", size: 10)
        let root = makeDirectory("/root", children: [child])

        XCTAssertNil(root.clonedSubtree(removingNodeWithID: root.id))
    }

    private func makeDirectory(_ path: String, children: [FileNode]) -> FileNode {
        let node = FileNode(url: URL(fileURLWithPath: path), isDirectory: true)
        node.children = children
        node.size = children.reduce(0) { $0 + $1.size }
        node.fileCount = children.reduce(0) { $0 + $1.fileCount }
        return node
    }

    private func makeFile(_ path: String, size: UInt64) -> FileNode {
        FileNode(url: URL(fileURLWithPath: path), isDirectory: false, size: size)
    }
}
