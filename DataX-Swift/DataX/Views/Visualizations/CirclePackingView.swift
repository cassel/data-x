import SwiftUI

struct CirclePackingView: View {
    let node: FileNode
    let onSelect: (FileNode) -> Void

    @State private var hoveredNode: FileNode?

    var body: some View {
        GeometryReader { geometry in
            let circles = packCircles(
                for: node,
                bounds: CGRect(origin: .zero, size: geometry.size)
            )

            ZStack {
                ForEach(circles, id: \.node.id) { circle in
                    CircleView(
                        circle: circle,
                        isHovered: hoveredNode?.id == circle.node.id
                    )
                    .onTapGesture(count: 2) {
                        if circle.node.isDirectory {
                            onSelect(circle.node)
                        }
                    }
                    .onHover { isHovered in
                        hoveredNode = isHovered ? circle.node : nil
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if let hoveredNode {
                    CircleInfoPanel(node: hoveredNode)
                        .padding()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    struct PackedCircle {
        let node: FileNode
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let depth: Int
    }

    private func packCircles(for rootNode: FileNode, bounds: CGRect) -> [PackedCircle] {
        guard let children = rootNode.sortedChildren, !children.isEmpty else { return [] }

        var circles: [PackedCircle] = []
        let totalSize = Double(children.reduce(0) { $0 + $1.size })
        guard totalSize > 0 else { return [] }

        let centerX = bounds.midX
        let centerY = bounds.midY
        let maxRadius = min(bounds.width, bounds.height) / 2 - 10

        // Simple circle packing using golden angle spiral
        let goldenAngle = .pi * (3 - sqrt(5))
        var placedCircles: [(x: CGFloat, y: CGFloat, r: CGFloat)] = []

        for (index, child) in children.prefix(50).enumerated() {
            let sizeRatio = Double(child.size) / totalSize
            let radius = max(15, CGFloat(sqrt(sizeRatio) * Double(maxRadius) * 0.4))

            // Use golden angle spiral for initial position
            let angle = CGFloat(index) * goldenAngle
            let spiralRadius = CGFloat(sqrt(Double(index))) * radius * 1.5

            var x = centerX + cos(angle) * spiralRadius
            var y = centerY + sin(angle) * spiralRadius

            // Adjust position to avoid overlaps
            var attempts = 0
            while attempts < 100 {
                var overlaps = false
                for placed in placedCircles {
                    let dx = x - placed.x
                    let dy = y - placed.y
                    let distance = sqrt(dx * dx + dy * dy)
                    let minDistance = radius + placed.r + 2

                    if distance < minDistance {
                        overlaps = true
                        // Push away
                        let pushAngle = atan2(dy, dx)
                        let pushDistance = minDistance - distance + 5
                        x += cos(pushAngle) * pushDistance
                        y += sin(pushAngle) * pushDistance
                        break
                    }
                }

                if !overlaps { break }
                attempts += 1
            }

            // Keep within bounds
            x = max(radius, min(bounds.width - radius, x))
            y = max(radius, min(bounds.height - radius, y))

            placedCircles.append((x, y, radius))
            circles.append(PackedCircle(
                node: child,
                x: x,
                y: y,
                radius: radius,
                depth: 0
            ))
        }

        return circles
    }
}

struct CircleView: View {
    let circle: CirclePackingView.PackedCircle
    let isHovered: Bool

    var body: some View {
        Circle()
            .fill(circleColor)
            .overlay {
                Circle()
                    .stroke(isHovered ? Color.white : Color.white.opacity(0.3), lineWidth: isHovered ? 2 : 1)
            }
            .overlay {
                if circle.radius > 25 {
                    VStack(spacing: 2) {
                        Image(systemName: circle.node.isDirectory ? "folder.fill" : circle.node.category.icon)
                            .font(.system(size: min(circle.radius * 0.3, 20)))
                        if circle.radius > 40 {
                            Text(circle.node.name)
                                .font(.system(size: min(circle.radius * 0.15, 12)))
                                .lineLimit(1)
                                .frame(maxWidth: circle.radius * 1.5)
                        }
                        if circle.radius > 50 {
                            Text(circle.node.formattedSize)
                                .font(.system(size: min(circle.radius * 0.12, 10)))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .foregroundColor(.white)
                }
            }
            .frame(width: circle.radius * 2, height: circle.radius * 2)
            .position(x: circle.x, y: circle.y)
    }

    private var circleColor: Color {
        let baseColor = circle.node.isDirectory
            ? FileCategory.folders.color
            : circle.node.category.color

        return isHovered ? baseColor.opacity(0.9) : baseColor.opacity(0.8)
    }
}

// MARK: - Info Panel

struct CircleInfoPanel: View {
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
    CirclePackingView(node: root) { _ in }
        .frame(width: 500, height: 500)
}
