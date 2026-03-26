import CoreGraphics
import Foundation
import SwiftUI

enum VisualizationKeyboardDirection {
    case left
    case right
    case up
    case down

    init?(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            self = .left
        case .right:
            self = .right
        case .up:
            self = .up
        case .down:
            self = .down
        @unknown default:
            return nil
        }
    }
}

enum VisualizationAccessibilityFormatter {
    static func percentText(part: UInt64, of total: UInt64) -> String {
        guard total > 0 else { return "0%" }

        let percent = (Double(part) / Double(total)) * 100
        let roundedPercent = (percent * 10).rounded() / 10

        if roundedPercent == roundedPercent.rounded() {
            return String(format: "%.0f%%", roundedPercent)
        }

        return String(format: "%.1f%%", roundedPercent)
    }

    static func treemapValue(
        sizeText: String,
        part: UInt64,
        parent: UInt64
    ) -> String {
        "\(sizeText), \(percentText(part: part, of: parent)) of parent"
    }

    static func sunburstValue(
        sizeText: String,
        depth: Int,
        part: UInt64,
        parent: UInt64? = nil
    ) -> String {
        var components = [sizeText]

        if let parent, parent > 0 {
            components.append("\(percentText(part: part, of: parent)) of parent")
        }

        components.append(depthText(depth))
        return components.joined(separator: ", ")
    }

    static func depthText(_ depth: Int) -> String {
        "depth level \(depth + 1)"
    }
}

struct TreemapAccessibilityNode {
    let id: UUID
    let frame: CGRect
    let depth: Int

    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

enum TreemapAccessibilityNavigation {
    static func nextID(
        from currentID: UUID,
        in nodes: [TreemapAccessibilityNode],
        direction: VisualizationKeyboardDirection
    ) -> UUID? {
        guard let current = nodes.first(where: { $0.id == currentID }) else { return nil }

        let candidates = nodes
            .filter { $0.id != currentID }
            .compactMap { candidate -> TreemapNavigationCandidate? in
                guard isCandidate(candidate.frame, in: direction, from: current.frame) else {
                    return nil
                }

                return TreemapNavigationCandidate(
                    node: candidate,
                    hasOrthogonalOverlap: orthogonalOverlap(
                        between: current.frame,
                        and: candidate.frame,
                        direction: direction
                    ) > 0,
                    primaryDistance: primaryDistance(
                        from: current.frame,
                        to: candidate.frame,
                        direction: direction
                    ),
                    secondaryDistance: secondaryDistance(
                        from: current.center,
                        to: candidate.center,
                        direction: direction
                    ),
                    depthDifference: abs(candidate.depth - current.depth)
                )
            }

        let overlappingCandidates = candidates.filter(\.hasOrthogonalOverlap)
        let rankedCandidates = overlappingCandidates.isEmpty ? candidates : overlappingCandidates

        return rankedCandidates.min(by: { lhs, rhs in
            if lhs.primaryDistance != rhs.primaryDistance {
                return lhs.primaryDistance < rhs.primaryDistance
            }

            if lhs.secondaryDistance != rhs.secondaryDistance {
                return lhs.secondaryDistance < rhs.secondaryDistance
            }

            if lhs.depthDifference != rhs.depthDifference {
                return lhs.depthDifference < rhs.depthDifference
            }

            if lhs.node.depth != rhs.node.depth {
                return lhs.node.depth > rhs.node.depth
            }

            if lhs.node.frame.minY != rhs.node.frame.minY {
                return lhs.node.frame.minY < rhs.node.frame.minY
            }

            return lhs.node.frame.minX < rhs.node.frame.minX
        })?.node.id
    }

    private static func isCandidate(
        _ candidate: CGRect,
        in direction: VisualizationKeyboardDirection,
        from current: CGRect
    ) -> Bool {
        switch direction {
        case .left:
            return candidate.maxX <= current.minX
        case .right:
            return candidate.minX >= current.maxX
        case .up:
            return candidate.maxY <= current.minY
        case .down:
            return candidate.minY >= current.maxY
        }
    }

    private static func orthogonalOverlap(
        between current: CGRect,
        and candidate: CGRect,
        direction: VisualizationKeyboardDirection
    ) -> CGFloat {
        switch direction {
        case .left, .right:
            return max(0, min(current.maxY, candidate.maxY) - max(current.minY, candidate.minY))
        case .up, .down:
            return max(0, min(current.maxX, candidate.maxX) - max(current.minX, candidate.minX))
        }
    }

    private static func primaryDistance(
        from current: CGRect,
        to candidate: CGRect,
        direction: VisualizationKeyboardDirection
    ) -> CGFloat {
        switch direction {
        case .left:
            return current.minX - candidate.maxX
        case .right:
            return candidate.minX - current.maxX
        case .up:
            return current.minY - candidate.maxY
        case .down:
            return candidate.minY - current.maxY
        }
    }

    private static func secondaryDistance(
        from current: CGPoint,
        to candidate: CGPoint,
        direction: VisualizationKeyboardDirection
    ) -> CGFloat {
        switch direction {
        case .left, .right:
            return abs(candidate.y - current.y)
        case .up, .down:
            return abs(candidate.x - current.x)
        }
    }
}

private struct TreemapNavigationCandidate {
    let node: TreemapAccessibilityNode
    let hasOrthogonalOverlap: Bool
    let primaryDistance: CGFloat
    let secondaryDistance: CGFloat
    let depthDifference: Int
}

struct SunburstAccessibilityNode {
    let id: UUID
    let depth: Int
    let startAngle: Double
    let endAngle: Double
    let parentID: UUID?

    var midAngle: Double {
        (startAngle + endAngle) / 2
    }
}

enum SunburstAccessibilityNavigation {
    static func nextID(
        from currentID: UUID,
        in nodes: [SunburstAccessibilityNode],
        direction: VisualizationKeyboardDirection
    ) -> UUID? {
        guard let current = nodes.first(where: { $0.id == currentID }) else { return nil }
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        switch direction {
        case .left:
            let siblings = nodes
                .filter { $0.depth == current.depth }
                .sorted(by: angularOrder)

            guard let index = siblings.firstIndex(where: { $0.id == current.id }),
                  index > 0 else {
                return nil
            }

            return siblings[index - 1].id

        case .right:
            let siblings = nodes
                .filter { $0.depth == current.depth }
                .sorted(by: angularOrder)

            guard let index = siblings.firstIndex(where: { $0.id == current.id }),
                  index < siblings.count - 1 else {
                return nil
            }

            return siblings[index + 1].id

        case .up:
            if let parentID = current.parentID,
               nodesByID[parentID] != nil {
                return parentID
            }

            let innerRing = nodes.filter { $0.depth == current.depth - 1 }
            return bestAngularMatch(for: current, in: innerRing)?.id

        case .down:
            let visibleChildren = nodes
                .filter { $0.depth == current.depth + 1 && $0.parentID == current.id }
                .sorted(by: angularOrder)

            if let firstChild = visibleChildren.first {
                return firstChild.id
            }

            let outerRing = nodes.filter { $0.depth == current.depth + 1 }
            return bestAngularMatch(for: current, in: outerRing)?.id
        }
    }

    private static func angularOrder(
        _ lhs: SunburstAccessibilityNode,
        _ rhs: SunburstAccessibilityNode
    ) -> Bool {
        if lhs.startAngle != rhs.startAngle {
            return lhs.startAngle < rhs.startAngle
        }

        return lhs.endAngle < rhs.endAngle
    }

    private static func bestAngularMatch(
        for current: SunburstAccessibilityNode,
        in candidates: [SunburstAccessibilityNode]
    ) -> SunburstAccessibilityNode? {
        candidates.max(by: { lhs, rhs in
            let lhsContainment = containmentRank(for: current, candidate: lhs)
            let rhsContainment = containmentRank(for: current, candidate: rhs)
            if lhsContainment != rhsContainment {
                return lhsContainment < rhsContainment
            }

            let lhsOverlap = angularOverlap(between: current, and: lhs)
            let rhsOverlap = angularOverlap(between: current, and: rhs)
            if lhsOverlap != rhsOverlap {
                return lhsOverlap < rhsOverlap
            }

            let lhsDistance = abs(lhs.midAngle - current.midAngle)
            let rhsDistance = abs(rhs.midAngle - current.midAngle)
            if lhsDistance != rhsDistance {
                return lhsDistance > rhsDistance
            }

            return lhs.startAngle > rhs.startAngle
        })
    }

    private static func containmentRank(
        for current: SunburstAccessibilityNode,
        candidate: SunburstAccessibilityNode
    ) -> Int {
        if candidate.startAngle <= current.midAngle && candidate.endAngle >= current.midAngle {
            return 2
        }

        if angularOverlap(between: current, and: candidate) > 0 {
            return 1
        }

        return 0
    }

    private static func angularOverlap(
        between current: SunburstAccessibilityNode,
        and candidate: SunburstAccessibilityNode
    ) -> Double {
        max(0, min(current.endAngle, candidate.endAngle) - max(current.startAngle, candidate.startAngle))
    }
}
