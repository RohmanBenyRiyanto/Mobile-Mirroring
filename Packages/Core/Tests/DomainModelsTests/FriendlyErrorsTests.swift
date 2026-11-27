import XCTest
@testable import DomainModels

final class FriendlyErrorsTests: XCTestCase {
    func testKnownFailuresGetPlainAdvice() {
        XCTAssertTrue(FriendlyErrors.explain("error: device unauthorized.")?.contains("Allow") == true)
        XCTAssertTrue(FriendlyErrors.explain("Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]")?.contains("space") == true)
        XCTAssertTrue(FriendlyErrors.explain("adb: error: failed to connect to 10.0.0.2:5555")?.contains("Wi-Fi") == true)
        XCTAssertNil(FriendlyErrors.explain("something nobody has seen"))
    }
}
