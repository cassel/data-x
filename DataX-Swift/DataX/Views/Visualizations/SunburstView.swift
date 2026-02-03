import SwiftUI

struct SunburstView: View {
    let node: FileNode
    let onSelect: (FileNode) -> Void

    @State private var hoveredNode: FileNode?
    @State private var computedArcs: [ArcData] = []

    private let maxDepth = 4
    private let innerRadius: CGFloat = 60

    struct ArcData: Identifiable {
        let id: UUID
        let node: FileNode
        let startAngle: Double
        let endAngle: Double
        let innerRadius: CGFloat
        let outerRadius: CGFloat
        let depth: Int

        init(node: FileNode, startAngle: Double, endAngle: Double, innerRadius: CGFloat, outerRadius: CGFloat, depth: Int) {
            self.id = node.id
            self.node = node
            self.startAngle = startAngle
            self.endAngle = endAngle
            self.innerRadius = innerRadius
            self.outerRadius = outerRadius
            self.depth = depth
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let maxRadius = min(geometry.size.width, geometry.size.height) / 2 - 20
            let arcData = arcs(for: node, maxRadius: maxRadius)

            ZStack {
                // Draw arcs
                ForEach(arcData) { arc in
                    SunburstArc(arc: arc, center: center, isHovered: hoveredNode?.id == arc.node.id)
                        .onTapGesture(count: 2) {
                            if arc.node.isDirectory {
                                onSelect(arc.node)
                            }
                        }
                        .onHover { isHovered in
                            hoveredNode = isHovered ? arc.node : nil
                        }
                }

                // Center circle
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: innerRadius * 2, height: innerRadius * 2)
                    .position(center)

                // Center label
                VStack(spacing: 4) {
                    Text(node.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(node.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: innerRadius * 1.8)
                .position(center)
            }
            .overlay(alignment: .topLeading) {
                if let hoveredNode {
                    SunburstInfoPanel(node: hoveredNode)
                        .padding()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func arcs(for rootNode: FileNode, maxRadius: CGFloat) -> [ArcData] {
        var result: [ArcData] = []
        let ringWidth = (maxRadius - innerRadius) / CGFloat(maxDepth)

        func processNode(_ node: FileNode, startAngle: Double, endAngle: Double, depth: Int) {
            guard depth < maxDepth else { return }
            guard let children = node.sortedChildren, !children.isEmpty else { return }

            let totalSize = Double(children.reduce(0) { $0 + $1.size })
            guard totalSize > 0 else { return }

            var currentAngle = startAngle

            for child in children {
                let angleSpan = (Double(child.size) / totalSize) * (endAngle - startAngle)
                let childEndAngle = currentAngle + angleSpan

                // Only add arc if it's visible (> 0.5 degrees)
                if angleSpan > 0.5 * .pi / 180 {
                    let arc = ArcData(
                        node: child,
                        startAngle: currentAngle,
                        endAngle: childEndAngle,
                        innerRadius: innerRadius + CGFloat(depth) * ringWidth,
                        outerRadius: innerRadius + CGFloat(depth + 1) * ringWidth - 1,
                        depth: depth
                    )
                    result.append(arc)

                    // Recursively process children
                    if child.isDirectory {
                        processNode(child, startAngle: currentAngle, endAngle: childEndAngle, depth: depth + 1)
                    }
                }

                currentAngle = childEndAngle
            }
        }

        processNode(rootNode, startAngle: 0, endAngle: 2 * .pi, depth: 0)
        return result
    }
}

struct SunburstArc: View {
    let arc: SunburstView.ArcData
    let center: CGPoint
    let isHovered: Bool

    var body: some View {
        Path { path in
            path.addArc(
                center: center,
                radius: arc.outerRadius,
                startAngle: .radians(arc.startAngle - .pi / 2),
                endAngle: .radians(arc.endAngle - .pi / 2),
                clockwise: false
            )
            path.addArc(
                center: center,
                radius: arc.innerRadius,
                startAngle: .radians(arc.endAngle - .pi / 2),
                endAngle: .radians(arc.startAngle - .pi / 2),
                clockwise: true
            )
            path.closeSubpath()
        }
        .fill(arcColor)
        .overlay {
            Path { path in
                path.addArc(
                    center: center,
                    radius: arc.outerRadius,
                    startAngle: .radians(arc.startAngle - .pi / 2),
                    endAngle: .radians(arc.endAngle - .pi / 2),
                    clockwise: false
                )
                path.addArc(
                    center: center,
                    radius: arc.innerRadius,
                    startAngle: .radians(arc.endAngle - .pi / 2),
                    endAngle: .radians(arc.startAngle - .pi / 2),
                    clockwise: true
                )
                path.closeSubpath()
            }
            .stroke(isHovered ? Color.white : Color.white.opacity(0.3), lineWidth: isHovered ? 2 : 0.5)
        }
    }

    private var arcColor: Color {
        let baseColor = arc.node.isDirectory
            ? FileCategory.folders.color
            : arc.node.category.color

        let depthFactor = 1.0 - Double(arc.depth) * 0.15
        return isHovered
            ? baseColor.opacity(0.9)
            : baseColor.opacity(depthFactor)
    }
}

// MARK: - Info Panel

struct SunburstInfoPanel: View {
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
    SunburstView(node: root) { _ in }
        .frame(width: 500, height: 500)
}
