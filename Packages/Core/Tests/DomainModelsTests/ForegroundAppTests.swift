import XCTest
@testable import DomainModels
@testable import Persistence

final class ForegroundAppParserTests: XCTestCase {
    /// Captured from a Samsung SM-S911B on Android 17.
    private let launcher = """
      mCurrentFocus=Window{d3d3625 u0 com.sec.android.app.launcher/com.sec.android.app.launcher.activities.LauncherActivity}
      mFocusedApp=ActivityRecord{147039174 u0 com.sec.android.app.launcher/.activities.LauncherActivity t738}
        mFocusedWindow=Window{d3d3625 u0 com.sec.android.app.launcher/com.sec.android.app.launcher.activities.LauncherActivity}
    """

    func testParsesTheRealLauncherOutput() {
        XCTAssertEqual(ForegroundAppParser.parse(launcher),
                       ForegroundApp(package: "com.sec.android.app.launcher", activity: ".activities.LauncherActivity"))
    }

    func testTheFocusedAppWinsWhileASystemWindowHasFocus() {
        let output = """
          mCurrentFocus=Window{1a2b3c u0 NotificationShade}
          mFocusedApp=ActivityRecord{99 u0 com.example.game/.MainActivity t12}
        """
        XCTAssertEqual(ForegroundAppParser.parse(output)?.package, "com.example.game")
    }

    func testFallsBackToTheFocusedWindowWhenNoAppIsFocused() {
        let output = """
          mCurrentFocus=Window{abc u0 com.example.app/com.example.app.Main}
          mFocusedApp=null
        """
        XCTAssertEqual(ForegroundAppParser.parse(output),
                       ForegroundApp(package: "com.example.app", activity: "com.example.app.Main"))
    }

    func testWorkProfileUsersAreRecognised() {
        XCTAssertEqual(ForegroundAppParser.parse("mFocusedApp=ActivityRecord{1 u10 com.work.app/.Home t3}")?.package, "com.work.app")
    }

    func testNothingFocusedGivesNil() {
        XCTAssertNil(ForegroundAppParser.parse("mCurrentFocus=null\nmFocusedApp=null"))
        XCTAssertNil(ForegroundAppParser.parse(""))
        XCTAssertNil(ForegroundAppParser.parse("mCurrentFocus=Window{abc u0 NotificationShade}"))
    }

    func testPackageNamesWithShellOrPathCharactersAreRejected() {
        for bad in ["com.evil;rm", "../../etc/passwd", "com.a b.c", "$(id).x", "com..x", ".com.x", "com.x.", "9com.x", "single"] {
            XCTAssertFalse(ForegroundApp.isValidPackage(bad), bad)
            XCTAssertNil(ForegroundAppParser.parse("mFocusedApp=ActivityRecord{1 u0 \(bad)/.Main t1}"), bad)
        }
        for good in ["com.sec.android.app.launcher", "com.tencent.ig", "com.mobile_legends.v2", "a.b"] {
            XCTAssertTrue(ForegroundApp.isValidPackage(good), good)
        }
    }

    func testTheQueryIsAFixedConstant() {
        XCTAssertFalse(ForegroundAppParser.command.contains("$"))
        XCTAssertTrue(ForegroundAppParser.command.hasPrefix("dumpsys window"))
    }
}

@MainActor
final class ForegroundAppDetectorTests: XCTestCase {
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var outputs: [String]
        init(_ outputs: [String]) { self.outputs = outputs }
        func next() -> String {
            lock.withLock { outputs.count > 1 ? outputs.removeFirst() : outputs[0] }
        }
    }

    private func focus(_ package: String) -> String { "mFocusedApp=ActivityRecord{1 u0 \(package)/.Main t1}" }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: Double = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testPublishesChangesAndKeepsTheLastAppThroughATransition() async {
        let script = Script([focus("com.a.one"), "mCurrentFocus=null\nmFocusedApp=null", focus("com.b.two")])
        let detector = ForegroundAppDetector()
        var seen: [String] = []
        let observation = detector.$current.sink { if let package = $0?.package { seen.append(package) } }
        defer { observation.cancel() }

        detector.start(interval: .milliseconds(20)) { script.next() }
        await waitUntil { detector.current?.package == "com.b.two" }
        detector.stop()

        XCTAssertEqual(seen, ["com.a.one", "com.b.two"], "the null transition must not clear the app, and repeats must not republish")
        XCTAssertNil(detector.current, "stopping clears the app")
    }

    func testFetchFailuresAreIgnored() async {
        struct Failure: Error {}
        let detector = ForegroundAppDetector()
        detector.start(interval: .milliseconds(10)) { throw Failure() }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(detector.current)
        detector.stop()
    }
}
