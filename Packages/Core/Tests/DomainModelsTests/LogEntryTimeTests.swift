import XCTest
@testable import DomainModels

final class LogEntryTimeTests: XCTestCase {
    func testTimeComesFromTheThreadtimeLine() {
        let entry = LogEntry.parse("11-27 17:12:46.513  1234  1250 I ActivityManager: Start proc", id: 1)
        XCTAssertEqual(entry.time, "17:12:46.513")
        XCTAssertEqual(entry.tag, "ActivityManager")
    }

    func testBannersHaveNoTime() {
        XCTAssertEqual(LogEntry.parse("--- beginning of crash", id: 2).time, "")
    }
}
