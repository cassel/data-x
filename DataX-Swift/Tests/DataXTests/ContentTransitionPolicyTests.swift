import XCTest
@testable import DataX

final class ContentTransitionPolicyTests: XCTestCase {
    func testPhaseUsesWelcomeWhenNoScanAndNoResults() {
        XCTAssertEqual(
            ContentViewPhase.resolve(isScanning: false, rootNode: nil),
            .welcome
        )
    }

    func testPhasePrefersScanningWhileScanIsStillActive() {
        let rootNode = FileNode(url: URL(fileURLWithPath: "/scan-root"), isDirectory: true)

        XCTAssertEqual(
            ContentViewPhase.resolve(isScanning: true, rootNode: rootNode),
            .scanning
        )
    }

    func testPhaseUsesScannedOnceRootNodeExistsAndScanningStops() {
        let rootNode = FileNode(url: URL(fileURLWithPath: "/scan-root"), isDirectory: true)

        XCTAssertEqual(
            ContentViewPhase.resolve(isScanning: false, rootNode: rootNode),
            .scanned
        )
    }

    func testStandardMotionUsesSpatialHeroAndDirectionalResultsPaneTransition() {
        let policy = ContentTransitionMotionPolicy(reduceMotion: false)

        XCTAssertTrue(policy.usesSpatialHero)
        XCTAssertFalse(policy.usesOpacityOnlyPhaseTransitions)
        XCTAssertTrue(policy.usesDirectionalResultsPaneTransition)
    }

    func testReducedMotionFallsBackToOpacityOnlyTransitions() {
        let policy = ContentTransitionMotionPolicy(reduceMotion: true)

        XCTAssertFalse(policy.usesSpatialHero)
        XCTAssertTrue(policy.usesOpacityOnlyPhaseTransitions)
        XCTAssertFalse(policy.usesDirectionalResultsPaneTransition)
        XCTAssertFalse(policy.usesDirectionalVisualizationNavigationTransition)
    }

    func testStandardMotionKeepsDirectionalVisualizationNavigationTransitions() {
        let policy = ContentTransitionMotionPolicy(reduceMotion: false)

        XCTAssertTrue(policy.usesDirectionalVisualizationNavigationTransition)
    }

    func testSwipeIntentTreatsRightSwipeAsBackWhenHistoryExists() {
        XCTAssertEqual(
            SwipeNavigationIntent.resolve(deltaX: -12, deltaY: 1, canNavigateBack: true),
            .back
        )
    }

    func testSwipeIntentIgnoresLeftSwipe() {
        XCTAssertEqual(
            SwipeNavigationIntent.resolve(deltaX: 12, deltaY: 1, canNavigateBack: true),
            .ignore
        )
    }

    func testSwipeIntentIgnoresRootLevelSwipeEvenIfDirectionIsBack() {
        XCTAssertEqual(
            SwipeNavigationIntent.resolve(deltaX: -12, deltaY: 1, canNavigateBack: false),
            .ignore
        )
    }

    func testSwipeIntentIgnoresVerticalDominantGesture() {
        XCTAssertEqual(
            SwipeNavigationIntent.resolve(deltaX: -3, deltaY: 10, canNavigateBack: true),
            .ignore
        )
    }

    func testNavigationDirectionUsesForwardAnimationWhenDepthIncreases() {
        XCTAssertEqual(
            VisualizationNavigationDirection.resolve(fromDepth: 2, toDepth: 3),
            .forward
        )
    }

    func testNavigationDirectionUsesBackwardAnimationWhenDepthDecreases() {
        XCTAssertEqual(
            VisualizationNavigationDirection.resolve(fromDepth: 3, toDepth: 2),
            .backward
        )
    }

    func testNavigationDirectionUsesNeutralAnimationWhenDepthIsUnchanged() {
        XCTAssertEqual(
            VisualizationNavigationDirection.resolve(fromDepth: 2, toDepth: 2),
            .neutral
        )
    }
}
