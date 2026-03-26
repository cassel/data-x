import XCTest
import SwiftUI
@testable import DataX

final class VisualizationZoomStateTests: XCTestCase {
    func testEffectiveScaleRubberBandsBeyondMaximumWhenReduceMotionIsDisabled() {
        let zoomState = VisualizationZoomState(committedScale: 4.5, committedAnchor: .center)

        let effectiveScale = zoomState.effectiveScale(
            gestureMagnification: 1.5,
            reduceMotion: false
        )

        XCTAssertGreaterThan(effectiveScale, VisualizationZoomState.scaleRange.upperBound)
        XCTAssertLessThan(effectiveScale, 6.75)
    }

    func testEffectiveScaleClampsDirectlyWhenReduceMotionIsEnabled() {
        let zoomState = VisualizationZoomState(committedScale: 4.5, committedAnchor: .center)

        let effectiveScale = zoomState.effectiveScale(
            gestureMagnification: 1.5,
            reduceMotion: true
        )

        XCTAssertEqual(effectiveScale, VisualizationZoomState.scaleRange.upperBound)
    }

    func testCommitClampsScaleAndStoresGestureAnchor() {
        var zoomState = VisualizationZoomState()

        zoomState.commit(
            gestureMagnification: 6,
            gestureAnchor: .topLeading
        )

        XCTAssertEqual(zoomState.committedScale, VisualizationZoomState.scaleRange.upperBound)
        XCTAssertEqual(zoomState.committedAnchor, .topLeading)
        XCTAssertTrue(zoomState.canReset)
    }

    func testCommitResetsAnchorWhenScaleReturnsToDefault() {
        var zoomState = VisualizationZoomState(
            committedScale: 3,
            committedAnchor: .bottomTrailing
        )

        zoomState.commit(
            gestureMagnification: 0.2,
            gestureAnchor: .topLeading
        )

        XCTAssertEqual(zoomState.committedScale, VisualizationZoomState.scaleRange.lowerBound)
        XCTAssertEqual(zoomState.committedAnchor, .center)
        XCTAssertFalse(zoomState.canReset)
    }

    func testInverseContentTransformMatchesForwardTransform() {
        let size = CGSize(width: 200, height: 100)
        let contentPoint = CGPoint(x: 60, y: 40)
        let scale: CGFloat = 2
        let anchor = UnitPoint.topLeading

        let transformedPoint = VisualizationZoomState.viewPoint(
            for: contentPoint,
            in: size,
            scale: scale,
            anchor: anchor
        )
        let recoveredPoint = VisualizationZoomState.contentPoint(
            for: transformedPoint,
            in: size,
            scale: scale,
            anchor: anchor
        )

        XCTAssertEqual(transformedPoint.x, 120, accuracy: 0.001)
        XCTAssertEqual(transformedPoint.y, 80, accuracy: 0.001)
        XCTAssertEqual(recoveredPoint.x, contentPoint.x, accuracy: 0.001)
        XCTAssertEqual(recoveredPoint.y, contentPoint.y, accuracy: 0.001)
    }

    func testDoubleTapIntentPrefersResetOnlyAboveUnityZoom() {
        XCTAssertFalse(VisualizationZoomState.prefersResetDoubleTap(totalScale: 1))
        XCTAssertTrue(VisualizationZoomState.prefersResetDoubleTap(totalScale: 1.01))
    }
}
