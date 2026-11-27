import DomainModels
import Networking
import XCTest
@testable import WorkspaceFeature

private final class Commands: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [[String]] = []
    func add(_ c: [String]) { lock.withLock { items.append(c) } }
    var all: [[String]] { lock.withLock { items } }
}

@MainActor
final class TrafficModelTests: XCTestCase {
    func testStartSetsTheProxyAndStopRestoresTheOldValue() {
        let commands = Commands()
        let traffic = TrafficModel { args in
            commands.add(args)
            return args.last == "settings get global http_proxy" ? "10.0.0.5:3128\n" : ""
        }
        traffic.start()
        XCTAssertTrue(traffic.isOn)
        XCTAssertTrue(commands.all.contains { $0.first == "reverse" })
        XCTAssertTrue(commands.all.contains { ($0.last ?? "").hasPrefix("settings put global http_proxy 127.0.0.1:") })
        traffic.stop()
        XCTAssertFalse(traffic.isOn)
        XCTAssertTrue(commands.all.contains { $0.last == "settings put global http_proxy 10.0.0.5:3128" })
        XCTAssertTrue(commands.all.contains { $0.first == "reverse" && $0.contains("--remove") })
    }

    func testNoPreviousProxyIsClearedNotLeftBehind() {
        let commands = Commands()
        let traffic = TrafficModel { args in commands.add(args); return args.last == "settings get global http_proxy" ? "null\n" : "" }
        traffic.start()
        traffic.stop()
        XCTAssertTrue(commands.all.contains { $0.last == "settings put global http_proxy :0" })
        XCTAssertTrue(commands.all.contains { $0.last == "settings delete global http_proxy" })
    }

    func testFailureLeavesItOffAndUndoesTheReverse() {
        let commands = Commands()
        struct Refused: Error {}
        let traffic = TrafficModel { args in
            commands.add(args)
            if (args.last ?? "").hasPrefix("settings put") { throw Refused() }
            return ""
        }
        traffic.start()
        XCTAssertFalse(traffic.isOn)
        XCTAssertNotNil(traffic.failure)
        XCTAssertTrue(commands.all.contains { $0.first == "reverse" && $0.contains("--remove") })
    }
}

@MainActor
final class TrafficLiveTests: XCTestCase {
    /// BENZMIRROR_TEST_SERIAL=<serial> swift test --filter TrafficLiveTests
    func testRealPhoneReachesTheMacProxyAndSettingIsRestored() async throws {
        guard let serial = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_SERIAL"] else { throw XCTSkip("Set BENZMIRROR_TEST_SERIAL") }
        let adb = try XCTUnwrap(ADB.locate())
        let run: @Sendable ([String]) throws -> String = { try String(decoding: adb.run(["-s", serial] + $0, timeout: 20), as: UTF8.self) }
        let before = try run(["shell", "settings get global http_proxy"])
        let traffic = TrafficModel(run: run)
        traffic.start()
        XCTAssertTrue(traffic.isOn)
        let proxy = try run(["shell", "settings get global http_proxy"]).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(proxy.hasPrefix("127.0.0.1:"))
        _ = try run(["shell", "curl -s -m 10 -o /dev/null -x \(proxy) http://example.com/"])
        try await Task.sleep(for: .seconds(1))
        traffic.flush()
        XCTAssertTrue(traffic.log.calls.contains { $0.host == "example.com" }, "calls: \(traffic.log.calls)")
        traffic.stop()
        XCTAssertEqual(try run(["shell", "settings get global http_proxy"]), before)
    }
}
