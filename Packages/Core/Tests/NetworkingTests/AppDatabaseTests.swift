import XCTest
import DomainModels
@testable import Networking

/// Needs a phone with a debug app that has databases:
///
///     BENZMIRROR_TEST_SERIAL=<serial> BENZMIRROR_TEST_DEBUG_PACKAGE=<package> swift test --filter AppDatabaseTests
final class AppDatabaseTests: XCTestCase {
    func testRefusesWritesAndBadNamesWithoutAPhone() throws {
        let adb = try XCTUnwrap(ADB.locate(), "adb is needed to build the object")
        XCTAssertThrowsError(try AppDatabase(adb: adb, serial: "x", package: "a; reboot"))
        let db = try AppDatabase(adb: adb, serial: "x", package: "com.example.app")
        defer { db.cleanUp() }
        XCTAssertThrowsError(try db.pull("../etc/passwd"))
        XCTAssertThrowsError(try db.query("DELETE FROM t", in: URL(fileURLWithPath: "/tmp/x")))
    }

    func testRealPhoneListsPullsAndQueries() throws {
        guard let serial = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_SERIAL"],
              let package = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_DEBUG_PACKAGE"] else { throw XCTSkip("Set BENZMIRROR_TEST_SERIAL and BENZMIRROR_TEST_DEBUG_PACKAGE") }
        let db = try AppDatabase(adb: try XCTUnwrap(ADB.locate()), serial: serial, package: package)
        defer { db.cleanUp() }
        let files = try db.listFiles().filter { $0.hasSuffix(".db") }
        let first = try XCTUnwrap(files.first)
        let file = try db.pull(first)
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type='table'", in: file)
        XCTAssertEqual(tables.first, ["name"])
    }

    func testNotDebuggableIsReportedPlainly() throws {
        guard let serial = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_SERIAL"] else { throw XCTSkip("Set BENZMIRROR_TEST_SERIAL") }
        let db = try AppDatabase(adb: try XCTUnwrap(ADB.locate()), serial: serial, package: "com.android.settings")
        defer { db.cleanUp() }
        XCTAssertThrowsError(try db.listFiles()) { XCTAssertEqual($0 as? AppDatabaseError, .notDebuggable) }
    }
}
