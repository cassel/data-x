import AppKit
import SwiftUI
import XCTest
@testable import DataX

final class TreemapPolishPolicyTests: XCTestCase {
    func testTreemapFillColorCapsOverlyBrightCategoryTones() {
        let baseBrightness = brightness(of: FileCategory.archives.color)
        let treemapBrightness = brightness(
            of: TreemapColorStyling.fillColor(from: FileCategory.archives.color, depth: 0)
        )

        XCTAssertLessThan(treemapBrightness, baseBrightness)
    }

    func testTreemapGradientKeepsTopLeftLighterThanBottomRight() {
        let fillColor = TreemapColorStyling.fillColor(from: FileCategory.documents.color, depth: 2)
        let style = TreemapColorStyling.shadingStyle(for: fillColor, depth: 2)

        XCTAssertGreaterThan(brightness(of: style.gradientStartColor), brightness(of: fillColor))
        XCTAssertLessThan(brightness(of: style.gradientEndColor), brightness(of: fillColor))
    }

    func testTreemapGradientGetsSubtlerAtGreaterDepth() {
        let shallowFill = TreemapColorStyling.fillColor(from: FileCategory.code.color, depth: 0)
        let deepFill = TreemapColorStyling.fillColor(from: FileCategory.code.color, depth: 5)

        let shallowStyle = TreemapColorStyling.shadingStyle(for: shallowFill, depth: 0)
        let deepStyle = TreemapColorStyling.shadingStyle(for: deepFill, depth: 5)

        XCTAssertGreaterThan(
            brightnessSpan(for: shallowStyle),
            brightnessSpan(for: deepStyle)
        )
    }

    func testLabelPolicyHidesLabelsWhenRectIsTooCramped() {
        let layout = TreemapLabelPolicy.makeLayout(
            name: "Documents",
            sizeText: "512 MB",
            in: CGRect(x: 0, y: 0, width: 56, height: 26),
            depth: 0
        )

        XCTAssertNil(layout)
    }

    func testLabelPolicyUsesTruncationAsLastMilePolish() {
        let layout = TreemapLabelPolicy.makeLayout(
            name: "VeryLongDirectoryNameThatNeedsTruncation",
            sizeText: "3.2 GB",
            in: CGRect(x: 0, y: 0, width: 104, height: 40),
            depth: 0
        )

        XCTAssertNotNil(layout)
        XCTAssertEqual(layout?.displayName.last, "…")
    }

    func testLabelPolicyDropsSizeLineBeforeCrowding() {
        let layout = TreemapLabelPolicy.makeLayout(
            name: "Photos",
            sizeText: "18.4 GB",
            in: CGRect(x: 0, y: 0, width: 100, height: 36),
            depth: 0
        )

        XCTAssertNotNil(layout)
        XCTAssertNil(layout?.sizeFrame)
    }

    func testLabelPolicyKeepsSizeLineWhenBothLinesFitComfortably() {
        let layout = TreemapLabelPolicy.makeLayout(
            name: "Photos",
            sizeText: "18.4 GB",
            in: CGRect(x: 0, y: 0, width: 164, height: 58),
            depth: 0
        )

        XCTAssertNotNil(layout)
        XCTAssertNotNil(layout?.sizeFrame)
    }

    @MainActor
    func testVisualizationCommandIgnoresSelectionWithoutActiveScan() {
        let appState = AppState()
        appState.selectedVisualization = .sunburst

        appState.selectVisualizationFromCommand(.treemap)

        XCTAssertEqual(appState.selectedVisualization, .sunburst)
    }

    @MainActor
    func testVisualizationCommandSelectsTreemapWhenScanExists() {
        let appState = AppState()
        appState.selectedVisualization = .sunburst
        appState.scannerViewModel.rootNode = FileNode(
            url: URL(fileURLWithPath: "/root"),
            isDirectory: true
        )

        appState.selectVisualizationFromCommand(.treemap)

        XCTAssertEqual(appState.selectedVisualization, .treemap)
    }

    private func brightness(of color: Color) -> CGFloat {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        NSColor(color).usingColorSpace(.extendedSRGB)?.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )

        return brightness
    }

    private func brightnessSpan(for style: TreemapShadingStyle) -> CGFloat {
        brightness(of: style.gradientStartColor) - brightness(of: style.gradientEndColor)
    }
}
