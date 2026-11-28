import DomainModels
import Networking
import XCTest
@testable import AppInspection

/// Needs a phone, Android Studio and a running debug app: `BENZMIRROR_TEST_SERIAL` and `BENZMIRROR_TEST_DEBUG_APP` (a package name).
/// It prints only host names and counts, never contents.
final class AppInspectorLiveTests: XCTestCase {
    func testLooksInsideARunningDebugApp() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let serial = env["BENZMIRROR_TEST_SERIAL"], let package = env["BENZMIRROR_TEST_DEBUG_APP"] else { throw XCTSkip("no phone or debug app given") }
        let adb = try XCTUnwrap(ADB.locate())
        let calls = LockedValue<[Int: APICall]>([:])
        let ended = LockedValue<String?>(nil)
        let session = AppInspectorSession(adb: adb, serial: serial, package: package, onCall: { call in calls.withLock { $0[call.id] = call } }, onEnded: { ended.set($0 ?? "ended") })
        try await session.start()
        defer { Task { await session.stop() } }

        // Bring the app to the front again so that it does what it does when it comes back.
        _ = try? adb.run(["-s", serial, "shell", "monkey -p \(package) -c android.intent.category.LAUNCHER 1"], timeout: 10)
        let deadline = Date().addingTimeInterval(90)
        while calls.get().values.filter(\.isFinished).count < 3, Date() < deadline { try await Task.sleep(for: .milliseconds(500)) }
        let all = calls.get().values
        print("inspected calls:", all.count, "hosts:", Set(all.map(\.host)).sorted(), "with bodies:", all.filter { !($0.details?.responseBody.isEmpty ?? true) }.count, "https:", all.filter { $0.url.hasPrefix("https") }.count)
        XCTAssertNil(ended.get())
    }
}
