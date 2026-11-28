import XCTest
@testable import Networking

final class ADBChoiceTests: XCTestCase {
    func testOnlyAWorkingAdbIsAccepted() throws {
        XCTAssertNil(ADB.custom(path: "/nonexistent/adb"))
        XCTAssertNil(ADB.custom(path: "/bin/ls"), "an executable that is not adb is refused")
        if let found = ADB.locate() {
            XCTAssertNotNil(ADB.custom(path: found.executable.path))
            XCTAssertEqual(ADB.locate(preferring: "/bin/ls")?.executable, found.executable, "a bad choice falls back to the automatic one")
        }
    }
}
