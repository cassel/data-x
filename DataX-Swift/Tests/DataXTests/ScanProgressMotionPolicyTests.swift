import XCTest
@testable import DataX

final class ScanProgressMotionPolicyTests: XCTestCase {
    func testStandardMotionEnablesPulseAndNumericRoll() {
        let policy = ScanProgressMotionPolicy(reduceMotion: false)

        XCTAssertTrue(policy.allowsSymbolPulse)
        XCTAssertTrue(policy.allowsNumericRoll)
    }

    func testReduceMotionDisablesPulseAndNumericRoll() {
        let policy = ScanProgressMotionPolicy(reduceMotion: true)

        XCTAssertFalse(policy.allowsSymbolPulse)
        XCTAssertFalse(policy.allowsNumericRoll)
    }

    func testElapsedHelpersUseDisplayedWholeSeconds() {
        XCTAssertEqual(ScanProgressMotionPolicy.elapsedDisplayValue(for: 59.9), 59)
        XCTAssertEqual(ScanProgressMotionPolicy.formattedElapsedTime(for: 59.9), "59s")
        XCTAssertEqual(ScanProgressMotionPolicy.formattedElapsedTime(for: 61.2), "1m 1s")
        XCTAssertEqual(ScanProgressMotionPolicy.formattedElapsedTime(for: 3_661.8), "1h 1m")
    }
}
