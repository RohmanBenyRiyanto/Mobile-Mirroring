import XCTest
@testable import DomainModels

final class ReconnectPolicyTests: XCTestCase {
    func testBackoffGrowsThenStops() {
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: 1), 1)
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: 4), 8)
        XCTAssertEqual(ReconnectPolicy.delay(forAttempt: ReconnectPolicy.maxAttempts), 15)
        XCTAssertNil(ReconnectPolicy.delay(forAttempt: ReconnectPolicy.maxAttempts + 1))
        XCTAssertNil(ReconnectPolicy.delay(forAttempt: 0))
        XCTAssertEqual(ReconnectPolicy.delays, ReconnectPolicy.delays.sorted())
    }
}
