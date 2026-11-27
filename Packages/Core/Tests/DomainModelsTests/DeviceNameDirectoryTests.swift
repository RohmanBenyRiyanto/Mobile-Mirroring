import XCTest
@testable import DomainModels

final class DeviceNameDirectoryTests: XCTestCase {
    private let directory = DeviceNameDirectory(models: ["sm-s911b": "Samsung Galaxy S23", "pixel 8": "Google Pixel 8"], devices: ["dm1q": "Samsung Galaxy S23"])

    func testModelThenCodename() {
        XCTAssertEqual(directory.name(model: "SM-S911B"), "Samsung Galaxy S23")
        XCTAssertEqual(directory.name(model: "Pixel_8"), "Google Pixel 8")
        XCTAssertEqual(directory.name(model: "Unknown", codename: "DM1Q"), "Samsung Galaxy S23")
        XCTAssertNil(directory.name(model: "Unknown", codename: "x"))
        XCTAssertNil(directory.name(model: nil))
    }

    func testDecodesTheFileFormat() {
        let json = Data(#"{"models":{"a":"A Phone"},"devices":{}}"#.utf8)
        XCTAssertEqual(DeviceNameDirectory(json: json)?.name(model: "A"), "A Phone")
        XCTAssertNil(DeviceNameDirectory(json: Data("nope".utf8)))
    }
}
