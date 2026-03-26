import CoreGraphics
import Foundation

struct TreemapHitTestEntry: Equatable {
    let id: UUID
    let rect: CGRect
    let depth: Int
    let area: CGFloat

    init(id: UUID, rect: CGRect, depth: Int, area: CGFloat? = nil) {
        self.id = id
        self.rect = rect
        self.depth = depth
        self.area = area ?? (rect.width * rect.height)
    }

    init(rect: TreemapRect) {
        self.init(
            id: rect.id,
            rect: rect.cgRect,
            depth: rect.depth,
            area: CGFloat(rect.area)
        )
    }

    var isIndexable: Bool {
        rect.width > 0 && rect.height > 0
    }

    func contains(_ point: CGPoint) -> Bool {
        TreemapSpatialGeometry.contains(rect, point: point)
    }
}

struct TreemapHitTestCache {
    let rects: [TreemapRect]
    let rectsByID: [UUID: TreemapRect]
    let spatialIndex: TreemapSpatialIndex?

    static let empty = TreemapHitTestCache(rects: [], rectsByID: [:], spatialIndex: nil)

    init(
        rects: [TreemapRect],
        bounds: CGRect,
        minCellSize: CGFloat = 8,
        bucketSize: Int = 12
    ) {
        self.rects = rects
        self.rectsByID = Dictionary(uniqueKeysWithValues: rects.map { ($0.id, $0) })

        guard bounds.width > 0, bounds.height > 0 else {
            self.spatialIndex = nil
            return
        }

        var index = TreemapSpatialIndex(
            bounds: bounds,
            minCellSize: minCellSize,
            bucketSize: bucketSize
        )
        var insertedEntry = false

        for rect in rects {
            let entry = TreemapHitTestEntry(rect: rect)
            guard entry.isIndexable else { continue }
            index.insert(entry)
            insertedEntry = true
        }

        self.spatialIndex = insertedEntry ? index : nil
    }

    private init(rects: [TreemapRect], rectsByID: [UUID: TreemapRect], spatialIndex: TreemapSpatialIndex?) {
        self.rects = rects
        self.rectsByID = rectsByID
        self.spatialIndex = spatialIndex
    }

    func rect(for id: UUID) -> TreemapRect? {
        rectsByID[id]
    }

    func hoveredRect(at point: CGPoint) -> TreemapRect? {
        guard let spatialIndex else { return nil }
        guard let resolved = TreemapHoverResolver.resolve(
            point: point,
            candidates: spatialIndex.candidates(at: point)
        ) else {
            return nil
        }

        return rectsByID[resolved.id]
    }
}

enum TreemapHoverResolver {
    static func resolve(
        point: CGPoint,
        candidates: [TreemapHitTestEntry]
    ) -> TreemapHitTestEntry? {
        var best: TreemapHitTestEntry?

        for candidate in candidates where candidate.contains(point) {
            guard let currentBest = best else {
                best = candidate
                continue
            }

            if isPreferred(candidate, over: currentBest) {
                best = candidate
            }
        }

        return best
    }

    private static func isPreferred(
        _ lhs: TreemapHitTestEntry,
        over rhs: TreemapHitTestEntry
    ) -> Bool {
        if lhs.depth != rhs.depth {
            return lhs.depth > rhs.depth
        }

        if abs(lhs.area - rhs.area) > 0.0001 {
            return lhs.area < rhs.area
        }

        if abs(lhs.rect.minY - rhs.rect.minY) > 0.0001 {
            return lhs.rect.minY < rhs.rect.minY
        }

        if abs(lhs.rect.minX - rhs.rect.minX) > 0.0001 {
            return lhs.rect.minX < rhs.rect.minX
        }

        if abs(lhs.rect.width - rhs.rect.width) > 0.0001 {
            return lhs.rect.width < rhs.rect.width
        }

        if abs(lhs.rect.height - rhs.rect.height) > 0.0001 {
            return lhs.rect.height < rhs.rect.height
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct TreemapSpatialIndex {
    private let root: Node

    init(bounds: CGRect, minCellSize: CGFloat = 8, bucketSize: Int = 12) {
        self.root = Node(
            bounds: bounds,
            minCellSize: minCellSize,
            bucketSize: bucketSize
        )
    }

    mutating func insert(_ entry: TreemapHitTestEntry) {
        guard entry.isIndexable else { return }
        guard root.intersects(entry.rect) else { return }
        root.insert(entry)
    }

    func candidates(at point: CGPoint) -> [TreemapHitTestEntry] {
        guard root.contains(point) else { return [] }

        var result: [TreemapHitTestEntry] = []
        root.collectCandidates(at: point, into: &result)
        return result
    }

    private final class Node {
        let bounds: CGRect
        let minCellSize: CGFloat
        let bucketSize: Int

        var entries: [TreemapHitTestEntry] = []
        var children: [Node]?

        init(bounds: CGRect, minCellSize: CGFloat, bucketSize: Int) {
            self.bounds = bounds
            self.minCellSize = minCellSize
            self.bucketSize = bucketSize
        }

        func insert(_ entry: TreemapHitTestEntry) {
            guard intersects(entry.rect) else { return }

            if let children, let childIndex = childIndex(containing: entry.rect, in: children) {
                children[childIndex].insert(entry)
                return
            }

            entries.append(entry)

            guard children == nil, shouldSubdivide else { return }

            let newChildren = makeChildren()
            children = newChildren
            redistributeEntries(into: newChildren)
        }

        func collectCandidates(at point: CGPoint, into result: inout [TreemapHitTestEntry]) {
            guard contains(point) else { return }

            result.append(contentsOf: entries)

            guard let children else { return }

            for child in children where child.contains(point) {
                child.collectCandidates(at: point, into: &result)
            }
        }

        func contains(_ point: CGPoint) -> Bool {
            TreemapSpatialGeometry.contains(bounds, point: point)
        }

        func intersects(_ rect: CGRect) -> Bool {
            TreemapSpatialGeometry.intersects(bounds, rect)
        }

        private var shouldSubdivide: Bool {
            entries.count > bucketSize &&
            bounds.width / 2 >= minCellSize &&
            bounds.height / 2 >= minCellSize
        }

        private func makeChildren() -> [Node] {
            let midX = bounds.midX
            let midY = bounds.midY

            return [
                Node(
                    bounds: CGRect(
                        x: bounds.minX,
                        y: bounds.minY,
                        width: midX - bounds.minX,
                        height: midY - bounds.minY
                    ),
                    minCellSize: minCellSize,
                    bucketSize: bucketSize
                ),
                Node(
                    bounds: CGRect(
                        x: midX,
                        y: bounds.minY,
                        width: bounds.maxX - midX,
                        height: midY - bounds.minY
                    ),
                    minCellSize: minCellSize,
                    bucketSize: bucketSize
                ),
                Node(
                    bounds: CGRect(
                        x: bounds.minX,
                        y: midY,
                        width: midX - bounds.minX,
                        height: bounds.maxY - midY
                    ),
                    minCellSize: minCellSize,
                    bucketSize: bucketSize
                ),
                Node(
                    bounds: CGRect(
                        x: midX,
                        y: midY,
                        width: bounds.maxX - midX,
                        height: bounds.maxY - midY
                    ),
                    minCellSize: minCellSize,
                    bucketSize: bucketSize
                )
            ]
        }

        private func redistributeEntries(into children: [Node]) {
            var retainedEntries: [TreemapHitTestEntry] = []
            retainedEntries.reserveCapacity(entries.count)

            for entry in entries {
                if let childIndex = childIndex(containing: entry.rect, in: children) {
                    children[childIndex].insert(entry)
                } else {
                    retainedEntries.append(entry)
                }
            }

            entries = retainedEntries
        }

        private func childIndex(containing rect: CGRect, in children: [Node]) -> Int? {
            for (index, child) in children.enumerated() where TreemapSpatialGeometry.contains(child.bounds, rect: rect) {
                return index
            }

            return nil
        }
    }
}

private enum TreemapSpatialGeometry {
    static func contains(_ rect: CGRect, point: CGPoint) -> Bool {
        point.x >= rect.minX &&
        point.x <= rect.maxX &&
        point.y >= rect.minY &&
        point.y <= rect.maxY
    }

    static func contains(_ outer: CGRect, rect inner: CGRect) -> Bool {
        inner.minX >= outer.minX &&
        inner.maxX <= outer.maxX &&
        inner.minY >= outer.minY &&
        inner.maxY <= outer.maxY
    }

    static func intersects(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        lhs.minX <= rhs.maxX &&
        lhs.maxX >= rhs.minX &&
        lhs.minY <= rhs.maxY &&
        lhs.maxY >= rhs.minY
    }
}
