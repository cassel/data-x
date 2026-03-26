import XCTest
@testable import DataX

final class MenuBarDiskGaugeTests: XCTestCase {
    func testSeverityThresholdsUseAccentAt75WarningAbove75AndCriticalAbove90() {
        XCTAssertEqual(DiskUsageSeverity.resolve(for: 75), .normal)
        XCTAssertEqual(DiskUsageSeverity.resolve(for: 75.01), .warning)
        XCTAssertEqual(DiskUsageSeverity.resolve(for: 90), .warning)
        XCTAssertEqual(DiskUsageSeverity.resolve(for: 90.01), .critical)
    }

    func testPreferredDiskInfoUsesLiveScanWithoutQueryingFallback() {
        let live = makeDiskInfo(volumeName: "Live Volume", path: "/Volumes/Live")

        let resolution = MenuBarDiskResolver.preferredDiskInfo(
            live: live,
            lastScannedURL: URL(fileURLWithPath: "/Volumes/Fallback/Folder")
        ) { _ in
            XCTFail("Fallback disk query should not run when live scan data exists")
            return live
        }

        guard case let .available(info, source) = resolution else {
            return XCTFail("Expected available disk info")
        }

        XCTAssertEqual(source, .liveScan)
        XCTAssertEqual(info.volumeName, "Live Volume")
        XCTAssertEqual(info.volumePath.standardizedFileURL.path, "/Volumes/Live")
    }

    func testPreferredDiskInfoFallsBackToLastScannedURLWhenLiveDataIsMissing() {
        let lastScannedURL = URL(fileURLWithPath: "/Volumes/Archive/Projects")
        let fallback = makeDiskInfo(volumeName: "Archive", path: "/Volumes/Archive")

        let resolution = MenuBarDiskResolver.preferredDiskInfo(
            live: nil,
            lastScannedURL: lastScannedURL,
            homeDirectory: URL(fileURLWithPath: "/Users/tester")
        ) { url in
            XCTAssertEqual(url.standardizedFileURL, lastScannedURL.standardizedFileURL)
            return fallback
        }

        guard case let .available(info, source) = resolution else {
            return XCTFail("Expected fallback disk info")
        }

        XCTAssertEqual(source, .fallbackLocalVolume)
        XCTAssertEqual(info.volumeName, "Archive")
    }

    func testPreferredDiskInfoFallsBackToHomeDirectoryOnFreshLaunch() {
        let homeDirectory = URL(fileURLWithPath: "/Users/tester")
        let fallback = makeDiskInfo(volumeName: "Macintosh HD", path: "/")

        let resolution = MenuBarDiskResolver.preferredDiskInfo(
            live: nil,
            lastScannedURL: nil,
            homeDirectory: homeDirectory
        ) { url in
            XCTAssertEqual(url.standardizedFileURL, homeDirectory.standardizedFileURL)
            return fallback
        }

        guard case let .available(info, source) = resolution else {
            return XCTFail("Expected home-directory fallback disk info")
        }

        XCTAssertEqual(source, .fallbackLocalVolume)
        XCTAssertEqual(info.volumeName, "Macintosh HD")
    }

    func testScanNowIntentRescansLastLocalDirectoryWhenAvailable() {
        let lastScannedURL = URL(fileURLWithPath: "/Users/tester/Documents")

        let intent = MenuBarScanNowIntent.resolve(lastScannedURL: lastScannedURL)

        guard case let .rescan(url) = intent else {
            return XCTFail("Expected a local rescan intent")
        }

        XCTAssertEqual(url.standardizedFileURL, lastScannedURL.standardizedFileURL)
    }

    func testScanNowIntentOpensFolderPickerWithoutPriorLocalScan() {
        let intent = MenuBarScanNowIntent.resolve(lastScannedURL: nil)

        guard case .openFolderPicker = intent else {
            return XCTFail("Expected the folder picker intent")
        }
    }

    private func makeDiskInfo(
        volumeName: String,
        path: String,
        totalSpace: UInt64 = 1_000,
        usedSpace: UInt64 = 640,
        freeSpace: UInt64 = 360
    ) -> DiskInfo {
        DiskInfo(
            totalSpace: totalSpace,
            usedSpace: usedSpace,
            freeSpace: freeSpace,
            volumeName: volumeName,
            volumePath: URL(fileURLWithPath: path)
        )
    }
}
