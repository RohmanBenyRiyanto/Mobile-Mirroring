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

    func testVirtualDisplayStartsAndFollowsAResize() async throws {
        guard let serial = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_SERIAL"] else { throw XCTSkip("Set BENZMIRROR_TEST_SERIAL to run against a real phone") }
        var settings = MirrorSettings()
        settings.virtualDisplay = VirtualDisplaySettings(isEnabled: true, startApp: ProcessInfo.processInfo.environment["BENZMIRROR_TEST_VD_APP"] ?? "com.android.settings")
        let session = ScrcpySession(adb: try XCTUnwrap(ADB.locate()), serial: serial, settings: settings)
        let log = EventLog()
        session.onEvent = { log.record($0) }
        try await Task.detached { try session.start() }.value
        defer { session.stop() }
        try await Task.sleep(for: .seconds(3))
        let first = log.snapshot.size
        let placement = (try? String(decoding: ADB.locate()!.run(["-s", serial, "shell", "dumpsys activity activities | grep -E 'Display #|topResumedActivity' | head -8"], timeout: 10), as: UTF8.self)) ?? ""
        print("DEVICE>> placement=\(placement)")
        session.send(.resizeDisplay(width: 1280, height: 720))
        try await Task.sleep(for: .seconds(3))
        let second = log.snapshot
        print("DEVICE>> vd first=\(String(describing: first)) after resize=\(String(describing: second.size)) events=\(second.events) fps=\(session.statistics.snapshot().framesPerSecond)")
        XCTAssertEqual(first, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(second.size, CGSize(width: 1280, height: 720))
        XCTAssertFalse(second.events.contains { $0.hasPrefix("ended:") }, "\(second.events)")
    }

    func testTouchesReachTheVirtualDisplay() async throws {
        guard let serial = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_SERIAL"] else { throw XCTSkip("Set BENZMIRROR_TEST_SERIAL to run against a real phone") }
        var settings = MirrorSettings()
        settings.virtualDisplay = VirtualDisplaySettings(isEnabled: true, startApp: "com.android.settings")
        let adb = try XCTUnwrap(ADB.locate())
        let session = ScrcpySession(adb: adb, serial: serial, settings: settings)
        let log = EventLog()
        session.onEvent = { log.record($0) }
        try await Task.detached { try session.start() }.value
        defer { session.stop() }
        try await Task.sleep(for: .seconds(3))
        _ = session.statistics.snapshot()
        try await Task.sleep(for: .seconds(2))
        let idle = session.statistics.snapshot().framesPerSecond
        let size = try XCTUnwrap(log.snapshot.size)
        // Settings' search bar sits near the top; a tap there animates the screen, which shows up as a burst of frames.
        let point = TouchPosition(x: Int32(size.width * 0.5), y: Int32(size.height * 0.12), frameWidth: UInt16(size.width), frameHeight: UInt16(size.height))
        session.send(.touch(.down, point, pressure: 1))
        try await Task.sleep(for: .milliseconds(80))
        session.send(.touch(.up, point, pressure: 0))
        try await Task.sleep(for: .seconds(1))
        let busy = session.statistics.snapshot().framesPerSecond
        print("DEVICE>> vd touch idle=\(idle) fps, after tap=\(busy) fps")
        XCTAssertGreaterThan(busy, idle + 3, "the tap did not change what is on the virtual display")
    }

    func testFingerStrokeFlingsTheVirtualDisplay() async throws {
        guard let serial = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_SERIAL"] else { throw XCTSkip("Set BENZMIRROR_TEST_SERIAL to run against a real phone") }
        var settings = MirrorSettings()
        settings.virtualDisplay = VirtualDisplaySettings(isEnabled: true, startApp: "com.android.settings")
        let session = ScrcpySession(adb: try XCTUnwrap(ADB.locate()), serial: serial, settings: settings)
        let log = EventLog()
        session.onEvent = { log.record($0) }
        try await Task.detached { try session.start() }.value
        defer { session.stop() }
        try await Task.sleep(for: .seconds(3))
        let size = try XCTUnwrap(log.snapshot.size)
        func send(_ outputs: [ScrollStroke.Output]) {
            for output in outputs {
                let (action, ratio): (TouchAction, CGPoint)
                switch output {
                case let .down(p): (action, ratio) = (.down, p)
                case let .move(p): (action, ratio) = (.move, p)
                case let .up(p): (action, ratio) = (.up, p)
                }
                let position = TouchPosition(x: Int32(ratio.x * size.width), y: Int32(ratio.y * size.height), frameWidth: UInt16(size.width), frameHeight: UInt16(size.height))
                session.send(.touch(action, position, pressure: action == .up ? 0 : 1))
            }
        }
        _ = session.statistics.snapshot()
        var stroke = ScrollStroke()
        send(stroke.begin(at: CGPoint(x: 0.5, y: 0.8)))
        for _ in 0..<12 {
            send(stroke.move(by: CGVector(dx: 0, dy: -0.04)))
            try await Task.sleep(for: .milliseconds(12))
        }
        send(stroke.end())
        try await Task.sleep(for: .seconds(1.5))
        let fps = session.statistics.snapshot().framesPerSecond
        print("DEVICE>> vd stroke fps over 1.5 s = \(fps)")
        XCTAssertGreaterThan(fps, 8, "a drag then release should scroll and keep flinging")
    }

    func testPhoneMicrophoneSourceStartsWithoutAudioErrors() async throws {
        guard let serial = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_SERIAL"] else { throw XCTSkip("Set BENZMIRROR_TEST_SERIAL to run against a real phone") }
        var settings = MirrorSettings()
        settings.audioSource = .mic
        let session = ScrcpySession(adb: try XCTUnwrap(ADB.locate()), serial: serial, settings: settings)
        let log = EventLog()
        session.onEvent = { log.record($0) }
        try await Task.detached { try session.start() }.value
        defer { session.stop() }
        try await Task.sleep(for: .seconds(3))
        let events = log.snapshot.events
        print("DEVICE>> mic events=\(events)")
        XCTAssertTrue(events.contains { $0.hasPrefix("started:") })
        XCTAssertFalse(events.contains("audioUnavailable"), "the phone refused to capture the microphone: \(events)")
        XCTAssertFalse(events.contains { $0.hasPrefix("ended:") })
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

        let url = try XCTUnwrap(session.streamURL)
        let port = try XCTUnwrap(UInt16(url.split(separator: ":").last?.split(separator: "/").first ?? ""))
        let viewer = try connectLoopback(port: port)
        viewer.setTimeouts(seconds: 3)
        try viewer.write(Data("GET /live.ts HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))

        // A still screen sends few frames, so the notification shade is toggled to keep the stream moving.
        var received = Data()
        let deadline = Date().addingTimeInterval(6)
        var nextToggle = Date()
        var opened = false
        while Date() < deadline {
            if Date() >= nextToggle {
                session.send(opened ? .collapsePanels : .expandNotificationPanel)
                opened.toggle()
                nextToggle = Date().addingTimeInterval(0.5)
            }
            if let chunk = try? viewer.readSome(limit: 1 << 20), !chunk.isEmpty { received.append(chunk) }
        }
        session.send(.collapsePanels)
        session.send(.expandNotificationPanel)
        try await Task.sleep(for: .milliseconds(300))
        session.send(.collapsePanels)

        let stats = session.statistics.snapshot()
        let state = log.snapshot
        print("DEVICE>> events=\(state.events) size=\(String(describing: state.size)) fps=\(stats.framesPerSecond) mbps=\(stats.megabitsPerSecond) jitter=\(stats.jitterMillis) received=\(received.count) viewers=\(session.streamViewerCount)")

        XCTAssertTrue(state.events.contains { $0.hasPrefix("started:") }, "session never started: \(state.events)")
        XCTAssertFalse(state.events.contains { $0.hasPrefix("ended:") }, "session ended early: \(state.events)")
        XCTAssertEqual(state.size, CGSize(width: 1080, height: 2340), "gaming preset streams at native resolution")
        XCTAssertGreaterThan(stats.framesPerSecond, 5)
        XCTAssertGreaterThan(stats.megabitsPerSecond, 0.01)
        XCTAssertGreaterThan(session.streamViewerCount, 0)

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
