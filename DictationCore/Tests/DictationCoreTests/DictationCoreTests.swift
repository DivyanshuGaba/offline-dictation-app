import XCTest
@testable import DictationCore

final class DictationCoreTests: XCTestCase {
    func testStatus() throws {
        XCTAssertEqual(DictationCore.status(), "DictationCore is ready")
    }
}
