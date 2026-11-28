import XCTest
@testable import DomainModels

final class DebuggableAppsTests: XCTestCase {
    func testOnlyDebuggableThirdPartyAppsAreListed() {
        let details = """
        Packages:
          Package [com.example.debugapp] (abc123):
            userId=10100
            pkg=Package{1 com.example.debugapp}
            flags=[ DEBUGGABLE HAS_CODE ALLOW_CLEAR_USER_DATA ]
          Package [com.example.release] (def456):
            flags=[ HAS_CODE ALLOW_CLEAR_USER_DATA ]
          Package [com.android.systemdebug] (000):
            pkgFlags=[ SYSTEM DEBUGGABLE HAS_CODE ]
          Package [com.example.second] (777):
            pkgFlags=[ DEBUGGABLE HAS_CODE ]
        """
        let thirdParty = DebuggableApps.parsePackageList("package:com.example.debugapp\npackage:com.example.release\npackage:com.example.second\nbroken line\n")
        XCTAssertEqual(thirdParty.count, 3)
        XCTAssertEqual(DebuggableApps.parse(details: details, among: thirdParty), ["com.example.debugapp", "com.example.second"])
        XCTAssertEqual(DebuggableApps.parse(details: details).count, 3, "without the list, system packages count too")
    }

    func testNoiseGivesNothing() {
        XCTAssertTrue(DebuggableApps.parse(details: "flags=[ DEBUGGABLE ]").isEmpty, "flags without a package above them are ignored")
        XCTAssertTrue(DebuggableApps.parsePackageList("").isEmpty)
    }
}
