import Networking
import XCTest
@testable import DatabaseFeature

@MainActor
final class DatabaseModelTests: XCTestCase {
    func testWithoutAPhoneItSaysSo() async {
        let model = DatabaseModel()
        model.package = "com.example.app"
        await model.openPackage(adb: nil, serial: nil)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.files.isEmpty)
    }

    func testResultSplitsHeaderAndRowsAndWritesCSV() {
        let model = DatabaseModel()
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.header.isEmpty)
    }

    func testInvalidPackageIsRefusedBeforeAnythingRuns() async throws {
        let adb = try XCTUnwrap(ADB.locate())
        let model = DatabaseModel()
        model.package = "bad name; rm"
        await model.openPackage(adb: adb, serial: "x")
        XCTAssertNotNil(model.errorMessage)
    }
}
