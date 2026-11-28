import XCTest
@testable import DomainModels

final class InstalledAppsTests: XCTestCase {
    private let launchable = """
    111 activities found:
      Activity #0:
        priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true
        com.android.chrome/com.google.android.apps.chrome.Main
      Activity #1:
        com.mobilechess.gp/com.moba.unityplugin.MobaGameUnityActivity
        com.spotify.music/.MainActivity
    """
    private let recents = "  * Recent #0: Task{a8a7fd7 #1035 type=standard A=10650:com.mobilechess.gp nonResizable U=0 visible=true}\n  * Recent #1: Task{b #9 type=standard A=10100:com.example.gone U=0}"

    func testRecentAppsComeFirstAndOnlyIfLaunchable() {
        let apps = InstalledApps.parse(launchableOutput: launchable, recentsOutput: recents)
        XCTAssertEqual(apps.map(\.package), ["com.mobilechess.gp", "com.android.chrome", "com.spotify.music"])
        XCTAssertTrue(apps[0].isRecent)
        XCTAssertFalse(apps[1].isRecent)
    }

    func testReadableNamesAreGuessedFromThePackage() {
        XCTAssertEqual(InstalledApps.displayName(for: "com.mobilechess.gp"), "Mobilechess")
        XCTAssertEqual(InstalledApps.displayName(for: "com.spotify.music"), "Music")
        XCTAssertEqual(InstalledApps.displayName(for: "com.android.chrome"), "Chrome")
    }

    func testSearchNeedsEveryWordInNameOrPackage() {
        let apps = InstalledApps.parse(launchableOutput: launchable, recentsOutput: recents)
        XCTAssertEqual(InstalledApps.filter(apps, query: "spot").map(\.package), ["com.spotify.music"])
        XCTAssertEqual(InstalledApps.filter(apps, query: "com chrome").count, 1)
        XCTAssertEqual(InstalledApps.filter(apps, query: "").count, 3)
        XCTAssertTrue(InstalledApps.filter(apps, query: "zzz").isEmpty)
    }

    func testGarbageLinesAreIgnored() {
        XCTAssertTrue(InstalledApps.parse(launchableOutput: "Error: nothing\nbad line with spaces/x", recentsOutput: "").isEmpty)
    }
}
