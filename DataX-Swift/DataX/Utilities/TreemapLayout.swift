import Foundation
import CoreGraphics
import SwiftUI

struct TreemapRect: Identifiable {
    let id: UUID
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    let node: FileNode
    let depth: Int
    let color: Color  // Pre-computed color

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var center: CGPoint {
        CGPoint(x: x + width / 2, y: y + height / 2)
    }

    var area: Double {
        width * height
    }

    func contains(_ point: CGPoint) -> Bool {
        point.x >= x && point.x <= x + width &&
        point.y >= y && point.y <= y + height
    }

    func inset(by amount: Double) -> TreemapRect {
        TreemapRect(
            id: id,
            x: x + amount,
            y: y + amount,
            width: max(0, width - amount * 2),
            height: max(0, height - amount * 2),
            node: node,
            depth: depth,
            color: color
        )
    }
}

enum TreemapLayout {
    // Cache for dominant colors to avoid recalculating
    private static var colorCache: [UUID: Color] = [:]

    static func layout(
        node: FileNode,
        bounds: CGRect,
        depth: Int = 0,
        maxDepth: Int = 6,
        maxRects: Int = 5000  // Limit total rects
    ) -> [TreemapRect] {
        colorCache.removeAll()  // Clear cache for new layout
        var rects: [TreemapRect] = []
        layoutRecursive(
            node: node,
            bounds: bounds,
            depth: depth,
            maxDepth: maxDepth,
            rects: &rects,
            maxRects: maxRects
        )
        return rects
    }

    private static func layoutRecursive(
        node: FileNode,
        bounds: CGRect,
        depth: Int,
        maxDepth: Int,
        rects: inout [TreemapRect],
        maxRects: Int
    ) {
        guard rects.count < maxRects else { return }
        guard let children = node.sortedChildren, !children.isEmpty else { return }
        guard bounds.width > 2 && bounds.height > 2 else { return }

        let totalSize = Double(children.reduce(0) { $0 + $1.size })
        guard totalSize > 0 else { return }

        var remaining: [(FileNode, Double)] = children.map { child in
            (child, Double(child.size) / totalSize * Double(bounds.width * bounds.height))
        }

        var currentBounds = bounds

        while !remaining.isEmpty && currentBounds.width > 1 && currentBounds.height > 1 && rects.count < maxRects {
            let isHorizontal = currentBounds.width >= currentBounds.height
            let (row, rest) = squarify(remaining, bounds: currentBounds, isHorizontal: isHorizontal)

            guard !row.isEmpty else { break }

            let rowTotalArea = row.reduce(0.0) { $0 + $1.1 }
            let side = isHorizontal ? Double(currentBounds.height) : Double(currentBounds.width)
            let rowLength = side > 0 ? rowTotalArea / side : 0

            guard rowLength > 0 else { break }

            var offset: Double = 0

            for (childNode, area) in row {
                guard rects.count < maxRects else { break }

                let length = area / rowLength
                let color = getColor(for: childNode, depth: depth)

                let rect: TreemapRect
                if isHorizontal {
                    rect = TreemapRect(
                        id: childNode.id,
                        x: Double(currentBounds.minX),
                        y: Double(currentBounds.minY) + offset,
                        width: rowLength,
                        height: length,
                        node: childNode,
                        depth: depth,
                        color: color
                    )
                } else {
                    rect = TreemapRect(
                        id: childNode.id,
                        x: Double(currentBounds.minX) + offset,
                        y: Double(currentBounds.minY),
                        width: length,
                        height: rowLength,
                        node: childNode,
                        depth: depth,
                        color: color
                    )
                }

                rects.append(rect)

                // Recursively layout children
                if depth < maxDepth && childNode.isDirectory && childNode.children?.isEmpty == false {
                    let insetAmount = max(0.5, 1.5 - Double(depth) * 0.15)
                    let childBounds = rect.inset(by: insetAmount).cgRect
                    let minSize = max(3.0, 8.0 - Double(depth))

                    if childBounds.width > minSize && childBounds.height > minSize {
                        layoutRecursive(
                            node: childNode,
                            bounds: childBounds,
                            depth: depth + 1,
                            maxDepth: maxDepth,
                            rects: &rects,
                            maxRects: maxRects
                        )
                    }
                }

                offset += length
            }

            // Update bounds for next iteration
            if isHorizontal {
                currentBounds = CGRect(
                    x: currentBounds.minX + rowLength,
                    y: currentBounds.minY,
                    width: currentBounds.width - rowLength,
                    height: currentBounds.height
                )
            } else {
                currentBounds = CGRect(
                    x: currentBounds.minX,
                    y: currentBounds.minY + rowLength,
                    width: currentBounds.width,
                    height: currentBounds.height - rowLength
                )
            }

            remaining = rest
        }
    }

    // MARK: - Color Calculation (cached)

    private static func getColor(for node: FileNode, depth: Int) -> Color {
        let baseColor: Color
        if node.isDirectory {
            if let cached = colorCache[node.id] {
                baseColor = cached
            } else if let children = node.children, !children.isEmpty {
                baseColor = computeDominantColor(for: node)
                colorCache[node.id] = baseColor
            } else {
                baseColor = FileCategory.folders.color
            }
        } else {
            baseColor = node.category.color
        }

        // Darken by depth
        let nsColor = NSColor(baseColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        let newB = max(0.25, b - CGFloat(depth) * 0.05)
        return Color(NSColor(hue: h, saturation: s, brightness: newB, alpha: a))
    }

    private static func computeDominantColor(for node: FileNode) -> Color {
        var sizes: [FileCategory: UInt64] = [:]
        countCategoriesLimited(node, &sizes, depth: 0, maxDepth: 3)  // Limit recursion
        return sizes.max(by: { $0.value < $1.value })?.key.color ?? FileCategory.folders.color
    }

    private static func countCategoriesLimited(_ node: FileNode, _ sizes: inout [FileCategory: UInt64], depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }
        if node.isDirectory {
            node.children?.prefix(100).forEach { countCategoriesLimited($0, &sizes, depth: depth + 1, maxDepth: maxDepth) }
        } else {
            sizes[node.category, default: 0] += node.size
        }
    }

    // MARK: - Squarify Algorithm

    private static func squarify(
        _ items: [(FileNode, Double)],
        bounds: CGRect,
        isHorizontal: Bool
    ) -> (row: [(FileNode, Double)], rest: [(FileNode, Double)]) {
        guard !items.isEmpty else { return ([], []) }

        var row: [(FileNode, Double)] = []
        var rest = items
        var bestRatio = Double.infinity

        while !rest.isEmpty {
            let next = rest.removeFirst()
            let testRow = row + [next]
            let ratio = worstRatio(testRow, bounds: bounds, isHorizontal: isHorizontal)

            if ratio <= bestRatio || row.isEmpty {
                row = testRow
                bestRatio = ratio
            } else {
                rest.insert(next, at: 0)
                break
            }
        }

        return (row, rest)
    }

    private static func worstRatio(
        _ row: [(FileNode, Double)],
        bounds: CGRect,
        isHorizontal: Bool
    ) -> Double {
        guard !row.isEmpty else { return .infinity }

        let totalArea = row.reduce(0.0) { $0 + $1.1 }
        let side = isHorizontal ? Double(bounds.height) : Double(bounds.width)

        guard side > 0 && totalArea > 0 else { return .infinity }

        let length = totalArea / side

        return row.map { item in
            let width = item.1 / length
            guard width > 0 && length > 0 else { return Double.infinity }
            return max(length / width, width / length)
        }.max() ?? .infinity
    }
}
