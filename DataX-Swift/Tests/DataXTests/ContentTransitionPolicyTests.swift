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
    }
}
