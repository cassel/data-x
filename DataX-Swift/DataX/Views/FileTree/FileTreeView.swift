import SwiftUI

struct FileTreeView: View {
    let node: FileNode
    let onSelect: (FileNode) -> Void

    @State private var selectedNode: FileNode?
    @State private var expandedNodes: Set<UUID> = []

    var body: some View {
        List {
            if let children = node.sortedChildren {
                ForEach(children) { child in
                    FileTreeRow(
                        node: child,
                        isSelected: selectedNode?.id == child.id,
                        expandedNodes: $expandedNodes,
                        onSelect: { node in
                            selectedNode = node
                        },
                        onDoubleClick: { node in
                            if node.isDirectory {
                                onSelect(node)
                            } else {
                                FileOperationsService.openFile(node.path)
                            }
                        }
                    )
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: FileNode.ID.self) { selection in
            if let nodeId = selection.first,
               let node = findNode(withId: nodeId) {
                contextMenuItems(for: node)
            }
        }
    }

    private func findNode(withId id: UUID) -> FileNode? {
        func search(in node: FileNode) -> FileNode? {
            if node.id == id { return node }
            for child in node.children ?? [] {
                if let found = search(in: child) {
                    return found
                }
            }
            return nil
        }
        return search(in: node)
    }

    @ViewBuilder
    private func contextMenuItems(for node: FileNode) -> some View {
        Button {
            if node.isDirectory {
                onSelect(node)
            }
        } label: {
            Label("Open", systemImage: "folder")
        }
        .disabled(!node.isDirectory)

        Button {
            FileOperationsService.revealInFinder(node.path)
        } label: {
            Label("Reveal in Finder", systemImage: "folder.badge.gearshape")
        }

        Divider()

        Button {
            FileOperationsService.copyPath(node.path)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Button {
            FileOperationsService.openInTerminal(node.path)
        } label: {
            Label("Open in Terminal", systemImage: "terminal")
        }

        Divider()

        Button(role: .destructive) {
            try? FileOperationsService.moveToTrash(node.path)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}

struct FileTreeRow: View {
    let node: FileNode
    let isSelected: Bool
    @Binding var expandedNodes: Set<UUID>
    let onSelect: (FileNode) -> Void
    let onDoubleClick: (FileNode) -> Void

    private var isExpanded: Bool {
        expandedNodes.contains(node.id)
    }

    var body: some View {
        if node.isDirectory && node.children?.isEmpty == false {
            DisclosureGroup(isExpanded: Binding(
                get: { isExpanded },
                set: { newValue in
                    if newValue {
                        expandedNodes.insert(node.id)
                    } else {
                        expandedNodes.remove(node.id)
                    }
                }
            )) {
                if let children = node.sortedChildren {
                    ForEach(children) { child in
                        FileTreeRow(
                            node: child,
                            isSelected: false,
                            expandedNodes: $expandedNodes,
                            onSelect: onSelect,
                            onDoubleClick: onDoubleClick
                        )
                    }
                }
            } label: {
                rowContent
            }
        } else {
            rowContent
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: node.isDirectory ? "folder.fill" : node.category.icon)
                .foregroundColor(node.isDirectory ? FileCategory.folders.color : node.category.color)
                .frame(width: 20)

            // Name
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Size
            Text(node.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)

            // Item count (for directories)
            if node.isDirectory {
                Text("\(node.fileCount) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }

            // Modified date
            if let date = node.modificationDate {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleClick(node)
        }
        .onTapGesture(count: 1) {
            onSelect(node)
        }
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
}

#Preview {
    let root = FileNode(url: URL(fileURLWithPath: "/test"), isDirectory: true)
    let child1 = FileNode(url: URL(fileURLWithPath: "/test/folder"), isDirectory: true)
    let child2 = FileNode(url: URL(fileURLWithPath: "/test/file.txt"), isDirectory: false)
    child1.size = 1024 * 1024
    child2.size = 1024
    root.children = [child1, child2]

    return FileTreeView(node: root) { _ in }
        .frame(width: 600, height: 400)
}
