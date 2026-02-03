import SwiftUI

struct IcicleView: View {
    let node: FileNode
    let onSelect: (FileNode) -> Void

    @State private var hoveredNode: FileNode?

    private let maxDepth = 6
    private let rowHeight: CGFloat = 40

    struct RectData: Identifiable {
        let id: UUID
        let node: FileNode
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let depth: Int

        var frame: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
                let rects = icicleLayout(for: node, bounds: CGRect(
                    origin: .zero,
                    size: CGSize(width: geometry.size.width, height: CGFloat(maxDepth) * rowHeight)
                ))

                ZStack(alignment: .topLeading) {
                    ForEach(rects) { rect in
                        IcicleRectView(
                            rect: rect,
                            isHovered: hoveredNode?.id == rect.node.id
                        )
                        .onTapGesture(count: 2) {
                            if rect.node.isDirectory {
                                onSelect(rect.node)
                            }
                        }
                        .onHover { isHovered in
                            hoveredNode = isHovered ? rect.node : nil
                        }
                    }
                }
                .frame(width: geometry.size.width, height: CGFloat(maxDepth) * rowHeight)
            }
            .overlay(alignment: .topLeading) {
                if let hoveredNode {
                    IcicleInfoPanel(node: hoveredNode)
                        .padding()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func icicleLayout(for rootNode: FileNode, bounds: CGRect) -> [RectData] {
        var result: [RectData] = []

        func processNode(_ node: FileNode, x: CGFloat, width: CGFloat, depth: Int) {
            guard depth < maxDepth else { return }
            guard width > 2 else { return }

            let rect = RectData(
                id: node.id,
                node: node,
                x: x,
                y: CGFloat(depth) * rowHeight,
                width: width - 1,
                height: rowHeight - 1,
                depth: depth
            )
            result.append(rect)

            guard let children = node.sortedChildren, !children.isEmpty else { return }

            let totalSize = Double(children.reduce(0) { $0 + $1.size })
            guard totalSize > 0 else { return }

            var currentX = x

            for child in children {
                let childWidth = (Double(child.size) / totalSize) * Double(width)
                if childWidth > 2 {
                    processNode(child, x: currentX, width: CGFloat(childWidth), depth: depth + 1)
                }
                currentX += CGFloat(childWidth)
            }
        }

        processNode(rootNode, x: 0, width: bounds.width, depth: 0)
        return result
    }
}

struct IcicleRectView: View {
    let rect: IcicleView.RectData
    let isHovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(rectColor)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isHovered ? Color.white : Color.white.opacity(0.2), lineWidth: isHovered ? 2 : 0.5)
            }
            .overlay {
                if rect.width > 50 {
                    HStack(spacing: 4) {
                        Image(systemName: rect.node.isDirectory ? "folder.fill" : rect.node.category.icon)
                            .font(.caption2)

                        Text(rect.node.name)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        if rect.width > 120 {
                            Text(rect.node.formattedSize)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
    }

    private var rectColor: Color {
        let baseColor = rect.node.isDirectory
            ? FileCategory.folders.color
            : rect.node.category.color

        let depthFactor = 1.0 - Double(rect.depth) * 0.1
        return isHovered
            ? baseColor.opacity(0.9)
            : baseColor.opacity(depthFactor)
    }
}

// MARK: - Info Panel

struct IcicleInfoPanel: View {
    let node: FileNode

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(node.isDirectory ? FileCategory.folders.color : node.category.color)
                .frame(width: 10, height: 10)

            Text(node.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Text("•")
                .foregroundColor(.secondary)

            Text(node.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)

            if node.isDirectory {
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(node.fileCount) items")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .cornerRadius(6)
    }
}

#Preview {
    let root = FileNode(url: URL(fileURLWithPath: "/test"), isDirectory: true)
    IcicleView(node: root) { _ in }
        .frame(width: 600, height: 300)
}
