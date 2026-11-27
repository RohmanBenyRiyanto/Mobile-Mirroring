import XCTest
import TestSupport
@testable import Networking
@testable import Media
@testable import DomainModels
@testable import CoreTestSupport

/// Runs a real mirroring session against a connected phone. Opt-in, because it needs hardware:
///
///     BENZMIRROR_TEST_SERIAL=<adb serial> swift test --filter DeviceIntegrationTests
final class DeviceIntegrationTests: XCTestCase {
    private final class EventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        private var size: CGSize?

        func record(_ event: ScrcpySession.Event) {
            lock.withLock {
                switch event {
                case let .started(name): events.append("started:\(name)")
                case let .resized(newSize): size = newSize; events.append("resized")
                case .audioUnavailable: events.append("audioUnavailable")
                case let .ended(reason): events.append("ended:\(reason ?? "nil")")
                case .clipboard: events.append("clipboard")
                case .recordingStopped: events.append("recordingStopped")
                }
            }
        }

        var snapshot: (events: [String], size: CGSize?) { lock.withLock { (events, size) } }
    }

    func testRealPhoneMirrorsAndServesAStreamForOBS() async throws {
        guard let serial = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_SERIAL"] else {
            throw XCTSkip("Set BENZMIRROR_TEST_SERIAL to run against a real phone")
        }
        let adb = try XCTUnwrap(ADB.locate())

        var settings = MirrorSettings()
        settings.quality = try XCTUnwrap(VideoQuality.values(for: .gaming))
        settings.obsStreamEnabled = true
        settings.obsStreamPort = 0 // any free port

        let session = ScrcpySession(adb: adb, serial: serial, settings: settings)
        let log = EventLog()
        session.onEvent = { log.record($0) }
        try await Task.detached { try session.start() }.value
        session.isMuted = true
        defer { session.stop() }

        // Watch the stream the way OBS would.
        let url = try XCTUnwrap(session.streamURL)
        let port = try XCTUnwrap(UInt16(url.split(separator: ":").last?.split(separator: "/").first ?? ""))
        let viewer = try connectLoopback(port: port)
        viewer.setTimeouts(seconds: 3)
        try viewer.write(Data("GET /live.ts HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))

        var received = Data()
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if let chunk = try? viewer.readSome(limit: 1 << 20), !chunk.isEmpty { received.append(chunk) }
        }
        session.send(.expandNotificationPanel) // exercise the control channel
        try await Task.sleep(for: .milliseconds(300))
        session.send(.collapsePanels)

        let stats = session.statistics.snapshot()
        let state = log.snapshot
        print("DEVICE>> events=\(state.events) size=\(String(describing: state.size)) fps=\(stats.framesPerSecond) mbps=\(stats.megabitsPerSecond) received=\(received.count) viewers=\(session.streamViewerCount)")

        XCTAssertTrue(state.events.contains { $0.hasPrefix("started:") }, "session never started: \(state.events)")
        XCTAssertFalse(state.events.contains { $0.hasPrefix("ended:") }, "session ended early: \(state.events)")
        XCTAssertEqual(state.size, CGSize(width: 1080, height: 2340), "gaming preset streams at native resolution")
        XCTAssertGreaterThan(stats.framesPerSecond, 5)
        XCTAssertGreaterThan(stats.megabitsPerSecond, 0.01)
        XCTAssertGreaterThan(session.streamViewerCount, 0)

        // The OBS stream must be a valid, decodable transport stream with the phone's picture.
        let headerEnd = try XCTUnwrap(received.range(of: Data("\r\n\r\n".utf8)), "no HTTP response")
        var body = Data(received[headerEnd.upperBound...])
        body.removeLast(body.count % 188) // the last packet may still be in flight
        XCTAssertGreaterThan(body.count, 188 * 100)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("phone.ts")
        try body.write(to: file)

        let probe = try runTool("ffprobe", ["-v", "error", "-show_streams", "-of", "json", file.path])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(probe.output.utf8)) as? [String: Any])
        let streams = try XCTUnwrap(json["streams"] as? [[String: Any]])
        let video = try XCTUnwrap(streams.first { $0["codec_type"] as? String == "video" })
        XCTAssertEqual(video["codec_name"] as? String, "h264")
        XCTAssertEqual(video["width"] as? Int, 1080)
        XCTAssertEqual(video["height"] as? Int, 2340)
        print("DEVICE>> streams=\(streams.compactMap { $0["codec_name"] as? String })")

        let decode = try runTool("ffmpeg", ["-v", "error", "-i", file.path, "-map", "0:v:0", "-f", "null", "-"])
        print("DEVICE>> ffmpeg status=\(decode.status) errors=\(decode.errors.debugDescription)")
        XCTAssertEqual(decode.status, 0)
    }
}
