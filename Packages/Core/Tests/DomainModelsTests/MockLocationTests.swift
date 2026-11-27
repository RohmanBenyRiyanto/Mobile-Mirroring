import XCTest
@testable import DomainModels

final class MockLocationTests: XCTestCase {
    func testParsingAcceptsCoordinatesAndRefusesTheRest() {
        XCTAssertEqual(MockLocation(text: " -6.2 , 106.8 ")?.latitude, -6.2)
        XCTAssertNil(MockLocation(text: "91, 0"))
        XCTAssertNil(MockLocation(text: "0, 181"))
        XCTAssertNil(MockLocation(text: "1,2,3"))
        XCTAssertNil(MockLocation(text: "a, b"))
        XCTAssertNil(MockLocation(text: "1; reboot, 2"))
    }

    func testCommandsUseFixedWordsAndFormattedNumbersOnly() {
        let place = MockLocation(latitude: -6.2088, longitude: 106.8456)!
        XCTAssertTrue(place.startCommand.hasPrefix("appops set --uid 2000 android:mock_location allow"))
        XCTAssertTrue(place.updateCommand.contains("--location -6.208800,106.845600"))
        XCTAssertEqual(place.updateCommand.components(separatedBy: "set-test-provider-location").count - 1, 2)
        XCTAssertTrue(MockLocation.stopCommand.hasSuffix("android:mock_location default"))
        XCTAssertEqual(MockLocation.presets.count, 5)
    }
}
