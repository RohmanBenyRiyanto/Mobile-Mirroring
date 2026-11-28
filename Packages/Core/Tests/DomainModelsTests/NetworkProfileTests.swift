import XCTest
@testable import DomainModels

final class NetworkProfileTests: XCTestCase {
    func testDelayFollowsTheSpeedLimit() {
        XCTAssertEqual(NetworkProfile.transferDelay(bytes: 50_000, kbps: 400), 1.0, accuracy: 0.001) // 400 kbit is 50 kB per second
        XCTAssertEqual(NetworkProfile.transferDelay(bytes: 1_000, kbps: 0), 0)
        XCTAssertEqual(NetworkProfile.transferDelay(bytes: 0, kbps: 400), 0)
        XCTAssertEqual(NetworkProfile.transferDelay(bytes: 10_000_000, kbps: 20), 5, "never longer than five seconds per chunk")
    }

    func testPresets() {
        XCTAssertTrue(NetworkProfile.unlimited.isUnlimited)
        XCTAssertFalse(NetworkProfile.preset(id: "slow3g").isUnlimited)
        XCTAssertEqual(NetworkProfile.preset(id: "unknown"), .unlimited)
        XCTAssertEqual(Set(NetworkProfile.presets.map(\.id)).count, NetworkProfile.presets.count)
    }
}
