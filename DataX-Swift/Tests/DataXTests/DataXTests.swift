import XCTest
@testable import DataX

final class DataXTests: XCTestCase {
    func testSizeFormatter() {
        XCTAssertEqual(SizeFormatter.format(1024), "1 KB")
        XCTAssertEqual(SizeFormatter.format(1024 * 1024), "1 MB")
        XCTAssertEqual(SizeFormatter.format(1024 * 1024 * 1024), "1 GB")
    }

    func testFileCategory() {
        XCTAssertEqual(FileCategory.categorize("swift"), .code)
        XCTAssertEqual(FileCategory.categorize("jpg"), .images)
        XCTAssertEqual(FileCategory.categorize("mp4"), .videos)
        XCTAssertEqual(FileCategory.categorize("zip"), .archives)
    }
}
