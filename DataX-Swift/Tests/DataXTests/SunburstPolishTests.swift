import XCTest
import SwiftUI
@testable import DataX

final class SunburstPolishTests: XCTestCase {
    func testPathResolverBuildsRootToNestedNodePath() {
        let root = makeDirectory("/root")
        let apps = makeDirectory("/root/Applications")
        let utilities = makeDirectory("/root/Applications/Utilities")
        let terminal = makeFile("/root/Applications/Utilities/Terminal.app", size: 400)

        utilities.children = [terminal]
        apps.children = [utilities]
        root.children = [apps]

        let path = FileNodePathResolver.path(from: root, to: terminal)

        XCTAssertEqual(path.map(\.name), ["root", "Applications", "Utilities", "Terminal.app"])
    }

    func testPathResolverFallsBackToRootWhenTargetIsOutsideTree() {
        let root = makeDirectory("/root")
        let other = makeDirectory("/other")

        let path = FileNodePathResolver.path(from: root, to: other)

        XCTAssertEqual(path.map(\.name), ["root"])
    }

    func testLabelPolicyHidesLabelsWhenArcIsTooCramped() {
        let arc = makeArc(
            name: "Documents",
            size: 2_000,
            startAngle: 0,
            endAngle: 0.18,
            innerRadius: 70,
            outerRadius: 84,
            depth: 0
        )

        XCTAssertNil(SunburstLabelPolicy.makeLayout(for: arc))
    }

    func testLabelPolicyDropsSizeBeforeArcGetsCrowded() {
        let arc = makeArc(
            name: "Photos",
            size: 18_400_000_000,
            startAngle: 0,
            endAngle: 0.62,
            innerRadius: 88,
            outerRadius: 118,
            depth: 0
        )

        let layout = SunburstLabelPolicy.makeLayout(for: arc)

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout?.name, "Photos")
        XCTAssertNil(layout?.sizeText)
    }

    func testLabelPolicyKeepsSizeWhenArcHasComfortableSpace() {
        let arc = makeArc(
            name: "Applications",
            size: 18_400_000_000,
            startAngle: 0,
            endAngle: 1.35,
            innerRadius: 94,
            outerRadius: 142,
            depth: 0
        )

        let layout = SunburstLabelPolicy.makeLayout(for: arc)

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout?.name, "Applications")
        XCTAssertNotNil(layout?.sizeText)
    }

    func testDrillMotionUsesRotationTowardSelectedArcWhenMotionIsAllowed() {
        let arc = makeArc(
            name: "Applications",
            size: 18_400_000_000,
            startAngle: .pi / 3,
            endAngle: .pi / 2,
            innerRadius: 94,
            outerRadius: 142,
            depth: 0
        )

        let plan = SunburstDrillMotionPolicy.plan(
            for: arc,
            in: CGSize(width: 800, height: 800),
            reduceMotion: false
        )

        XCTAssertNotEqual(plan.departure.rotation, 0, accuracy: 0.001)
        XCTAssertNotEqual(plan.arrival.rotation, 0, accuracy: 0.001)
        XCTAssertGreaterThan(abs(plan.departure.scale - 1), 0.05)
    }

    func testDrillMotionFallsBackToSubtleMotionWhenReduceMotionIsEnabled() {
        let arc = makeArc(
            name: "Applications",
            size: 18_400_000_000,
            startAngle: .pi / 3,
            endAngle: .pi / 2,
            innerRadius: 94,
            outerRadius: 142,
            depth: 0
        )

        let plan = SunburstDrillMotionPolicy.plan(
            for: arc,
            in: CGSize(width: 800, height: 800),
            reduceMotion: true
        )

        XCTAssertEqual(plan.departure.rotation, 0, accuracy: 0.001)
        XCTAssertEqual(plan.arrival.rotation, 0, accuracy: 0.001)
        XCTAssertLessThan(abs(plan.departure.scale - 1), 0.05)
        XCTAssertLessThan(abs(plan.arrival.scale - 1), 0.05)
    }

    @MainActor
    func testVisualizationCommandIgnoresSunburstSelectionWithoutActiveScan() {
        let appState = AppState()

        appState.selectVisualizationFromCommand(.sunburst)

        XCTAssertEqual(appState.selectedVisualization, .treemap)
    }

    @MainActor
    func testVisualizationCommandSelectsSunburstWhenScanExists() {
        let appState = AppState()
        appState.scannerViewModel.rootNode = makeDirectory("/root")

        appState.selectVisualizationFromCommand(.sunburst)

        XCTAssertEqual(appState.selectedVisualization, .sunburst)
    }

    private func makeArc(
        name: String,
        size: UInt64,
        startAngle: Double,
        endAngle: Double,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        depth: Int
    ) -> SunburstView.ArcData {
        let isDirectory = name != "Terminal.app"
        let node = FileNode(
            url: URL(fileURLWithPath: "/\(name)"),
            isDirectory: isDirectory,
            size: size
        )

        return SunburstView.ArcData(
            node: node,
            startAngle: startAngle,
            endAngle: endAngle,
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            depth: depth
        )
    }

    private func makeDirectory(_ path: String) -> FileNode {
        FileNode(url: URL(fileURLWithPath: path), isDirectory: true)
    }

    private func makeFile(_ path: String, size: UInt64) -> FileNode {
        FileNode(url: URL(fileURLWithPath: path), isDirectory: false, size: size)
    }
}
