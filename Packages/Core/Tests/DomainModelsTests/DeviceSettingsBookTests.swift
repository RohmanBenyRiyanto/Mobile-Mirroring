import XCTest
@testable import DomainModels

final class DeviceSettingsBookTests: XCTestCase {
    func testRecordsAndAppliesPerPhone() {
        var book = DeviceSettingsBook()
        var mine = MirrorSettings()
        mine.showTouches = true
        mine.audioEnabled = false
        book.record(mine, serial: "A")

        var base = MirrorSettings()
        base.obsStreamPort = 9000
        let applied = book.apply(to: base, serial: "A")
        XCTAssertTrue(applied.showTouches)
        XCTAssertFalse(applied.audioEnabled)
        XCTAssertEqual(applied.obsStreamPort, 9000, "app-wide settings are not overridden")
        XCTAssertEqual(book.apply(to: base, serial: "other"), base)
    }

    func testOldestPhoneIsForgottenAndRoundTrips() throws {
        var book = DeviceSettingsBook()
        for i in 0..<(DeviceSettingsBook.capacity + 3) { book.record(MirrorSettings(), serial: "S\(i)") }
        XCTAssertEqual(book.entries.count, DeviceSettingsBook.capacity)
        XCTAssertEqual(book.entries.first?.serial, "S3")
        let decoded = try XCTUnwrap(DeviceSettingsBook.decode(JSONEncoder().encode(book)))
        XCTAssertEqual(decoded, book)
        XCTAssertNil(DeviceSettingsBook.decode(Data(count: DeviceSettingsBook.maxBytes + 1)))
        book.forget(serial: "S3")
        XCTAssertEqual(book.entries.count, DeviceSettingsBook.capacity - 1)
    }
}
