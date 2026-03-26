import Foundation
import CoreGraphics
import AppKit
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
    let parentID: UUID?
    let parentName: String
    let parentSize: UInt64

    init(
        id: UUID,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        node: FileNode,
        depth: Int,
        color: Color,
        parentID: UUID? = nil,
        parentName: String? = nil,
        parentSize: UInt64? = nil
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.node = node
        self.depth = depth
        self.color = color
        self.parentID = parentID
        self.parentName = parentName ?? node.name
        self.parentSize = parentSize ?? node.size
    }

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
            color: color,
            parentID: parentID,
            parentName: parentName,
            parentSize: parentSize
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
                        color: color,
                        parentID: node.id,
                        parentName: node.name,
                        parentSize: node.size
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
                        color: color,
                        parentID: node.id,
                        parentName: node.name,
                        parentSize: node.size
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

        return TreemapColorStyling.fillColor(from: baseColor, depth: depth)
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

struct TreemapShadingStyle: Equatable {
    let fillColor: Color
    let gradientStartColor: Color
    let gradientEndColor: Color
}

enum TreemapColorStyling {
    static func fillColor(from baseColor: Color, depth: Int) -> Color {
        let components = hsbaComponents(for: baseColor)
        let isNeutral = components.saturation < 0.12

        let adjustedSaturation: CGFloat
        if isNeutral {
            adjustedSaturation = min(max(components.saturation * 1.1, 0.03), 0.18)
        } else {
            adjustedSaturation = min(max(components.saturation, 0.58), 0.9)
        }

        let brightnessCeiling: CGFloat = isNeutral ? 0.58 : 0.8
        let brightnessFloor: CGFloat = isNeutral ? 0.46 : 0.52
        let normalizedBrightness = min(max(components.brightness, brightnessFloor), brightnessCeiling)
        let depthDarkening = min(CGFloat(depth) * (isNeutral ? 0.025 : 0.032), isNeutral ? 0.14 : 0.18)
        let brightness = max(isNeutral ? 0.34 : 0.36, normalizedBrightness - depthDarkening)

        return makeColor(
            hue: components.hue,
            saturation: adjustedSaturation,
            brightness: brightness,
            alpha: components.alpha
        )
    }

    static func shadingStyle(for fillColor: Color, depth: Int) -> TreemapShadingStyle {
        let lightening = max(0.025, 0.055 - CGFloat(depth) * 0.004)
        let darkening = max(0.02, 0.05 - CGFloat(depth) * 0.0035)

        return TreemapShadingStyle(
            fillColor: fillColor,
            gradientStartColor: adjust(fillColor, brightnessDelta: lightening, saturationDelta: -0.02),
            gradientEndColor: adjust(fillColor, brightnessDelta: -darkening, saturationDelta: 0.015)
        )
    }

    private static func adjust(
        _ color: Color,
        brightnessDelta: CGFloat,
        saturationDelta: CGFloat
    ) -> Color {
        let components = hsbaComponents(for: color)
        let saturation = min(max(components.saturation + saturationDelta, 0), 1)
        let brightness = min(max(components.brightness + brightnessDelta, 0), 1)

        return makeColor(
            hue: components.hue,
            saturation: saturation,
            brightness: brightness,
            alpha: components.alpha
        )
    }

    private static func hsbaComponents(for color: Color) -> (
        hue: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat,
        alpha: CGFloat
    ) {
        let converted = NSColor(color).usingColorSpace(.extendedSRGB) ?? NSColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return (hue, saturation, brightness, alpha)
    }

    private static func makeColor(
        hue: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat,
        alpha: CGFloat
    ) -> Color {
        Color(
            NSColor(
                hue: hue,
                saturation: saturation,
                brightness: brightness,
                alpha: alpha
            )
        )
    }
}
