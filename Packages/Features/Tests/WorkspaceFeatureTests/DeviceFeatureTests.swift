import CryptoKit
import XCTest
import TestSupport
import FeatureTestSupport
import CoreTestSupport
@testable import DomainModels
@testable import InspectorFeature
@testable import LogcatFeature
@testable import Networking
@testable import Persistence
@testable import WorkspaceFeature

/// Exercises every feature against a real phone. Opt-in:
///
///     BENZMIRROR_TEST_SERIAL=<adb serial> swift test --filter DeviceFeatureTests
///
/// The tests only use reversible actions (notification shade, Home/Back, settings that are restored).
final class DeviceFeatureTests: XCTestCase {
    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ScrcpySession.Event] = []
        func record(_ event: ScrcpySession.Event) { lock.withLock { items.append(event) } }
        var all: [ScrcpySession.Event] { lock.withLock { items } }

        var clipboards: [String] { all.compactMap { if case let .clipboard(text) = $0 { return text } else { return nil } } }
        var ended: Bool { all.contains { if case .ended = $0 { return true } else { return false } } }
        var audioUnavailable: Bool { all.contains { if case .audioUnavailable = $0 { return true } else { return false } } }
    }

    private var serial: String!
    private var adb: ADB!
    private var workDirectory: URL!

    override func setUpWithError() throws {
        guard let serial = ProcessInfo.processInfo.environment["BENZMIRROR_TEST_SERIAL"] else {
            throw XCTSkip("Set BENZMIRROR_TEST_SERIAL to run against a real phone")
        }
        self.serial = serial
        adb = try XCTUnwrap(ADB.locate())
        workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory { try? FileManager.default.removeItem(at: workDirectory) }
    }

    // MARK: Helpers

    private func startSession(serial target: String? = nil, _ configure: (inout MirrorSettings) -> Void = { _ in }) async throws -> (ScrcpySession, Events) {
        var settings = MirrorSettings()
        settings.quality = try XCTUnwrap(VideoQuality.values(for: .gaming))
        configure(&settings)
        let session = ScrcpySession(adb: adb, serial: target ?? serial, settings: settings)
        let events = Events()
        session.onEvent = { events.record($0) }
        try await Task.detached { try session.start() }.value
        session.isMuted = true
        return (session, events)
    }

    private func screenshotDigest() throws -> String {
        let png = try adb.run(["-s", serial, "exec-out", "screencap", "-p"], timeout: 15)
        return SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
    }

    func shell(_ arguments: [String]) throws -> String {
        String(decoding: try adb.run(["-s", serial, "shell"] + arguments, timeout: 15), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func pause(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }

    private func tap(_ key: AndroidKeyCode, on session: ScrcpySession) {
        session.send(.keycode(.down, key))
        session.send(.keycode(.up, key))
    }

    private func position(_ x: Int32, _ y: Int32) -> TouchPosition {
        TouchPosition(x: x, y: y, frameWidth: 1080, frameHeight: 2340)
    }

    // MARK: Mirroring and input

    func testTouchSwipeKeysScrollAndPinchControlThePhone() async throws {
        let (session, events) = try await startSession()
        defer { session.stop() }

        tap(.home, on: session)
        try await pause(1.2)
        let home = try screenshotDigest()

        // A real touch gesture: drag down from the top edge to open the notification shade.
        session.send(.touch(.down, position(540, 8), pressure: 1))
        for step in 1...20 {
            session.send(.touch(.move, position(540, Int32(8 + step * 70)), pressure: 1))
            try await pause(0.01)
        }
        session.send(.touch(.up, position(540, 1408), pressure: 0))
        try await pause(1.2)
        let shade = try screenshotDigest()
        XCTAssertNotEqual(home, shade, "the swipe did not change the screen")

        // Scroll and a two-finger pinch inside the shade (harmless there).
        session.send(.scroll(position(540, 900), horizontal: 0, vertical: -4))
        var pinch = PinchGesture(center: position(540, 900))
        session.send(.touch(.down, pinch.fingers.first, pressure: 1, pointer: .finger))
        session.send(.touch(.down, pinch.fingers.second, pressure: 1, pointer: .virtualFinger))
        pinch.scale(by: 1.6)
        session.send(.touch(.move, pinch.fingers.first, pressure: 1, pointer: .finger))
        session.send(.touch(.move, pinch.fingers.second, pressure: 1, pointer: .virtualFinger))
        session.send(.touch(.up, pinch.fingers.first, pressure: 0, pointer: .finger))
        session.send(.touch(.up, pinch.fingers.second, pressure: 0, pointer: .virtualFinger))
        try await pause(0.6)

        // Back closes the shade again.
        session.send(.backOrScreenOn(.down))
        session.send(.backOrScreenOn(.up))
        try await pause(1.2)
        XCTAssertNotEqual(try screenshotDigest(), shade, "Back did not close the shade")

        // The panel messages and the remaining keys must be accepted without ending the session.
        session.send(.expandSettingsPanel)
        try await pause(0.8)
        XCTAssertNotEqual(try screenshotDigest(), home)
        session.send(.collapsePanels)
        for key in [AndroidKeyCode.volumeUp, .volumeDown, .dpadDown, .dpadUp, .escape] { tap(key, on: session) }
        session.send(.text("benzmirror"))
        tap(.home, on: session)
        try await pause(0.8)
        XCTAssertFalse(events.ended, "session ended during input: \(events.all)")
    }

    func testClipboardRoundTripsBetweenMacAndPhone() async throws {
        let (session, events) = try await startSession()
        defer { session.stop() }

        let secret = "benzmirror-clip-\(UUID().uuidString.prefix(8))"
        session.send(.setClipboard(secret, paste: false))
        try await pause(0.5)
        session.send(.getClipboard(.copy))
        try await pause(1.0)
        XCTAssertTrue(events.clipboards.contains(secret), "got \(events.clipboards)")
    }

    func testDisplayPowerCanBeToggled() async throws {
        let (session, events) = try await startSession()
        defer { session.stop() }
        session.send(.setDisplayPower(false))
        try await pause(0.8)
        session.send(.setDisplayPower(true))
        try await pause(0.8)
        XCTAssertFalse(events.ended)
        XCTAssertTrue(try shell(["dumpsys", "power"]).contains("mWakefulness=Awake"))
    }

    // MARK: Quality presets

    func testEveryPresetStartsAndStreamsOnThisPhone() async throws {
        for preset in [QualityPreset.balanced, .high, .gaming, .maximum] {
            let (session, events) = try await startSession { $0.quality = VideoQuality.values(for: preset)! }
            tap(.home, on: session)
            try await pause(2.5)
            let stats = session.statistics.snapshot()
            print("DEVICE>> preset=\(preset.rawValue) fps=\(String(format: "%.1f", stats.framesPerSecond)) mbps=\(String(format: "%.2f", stats.megabitsPerSecond)) ended=\(events.ended)")
            XCTAssertFalse(events.ended, "\(preset) ended: \(events.all)")
            XCTAssertGreaterThan(stats.framesPerSecond, 1, "\(preset) produced no video")
            session.stop()
            try await pause(0.8)
        }
    }

    func testH265StreamForOBSIsDecodable() async throws {
        let (session, _) = try await startSession {
            $0.quality = VideoQuality.values(for: .maximum)!
            $0.obsStreamEnabled = true
            $0.obsStreamPort = 0
        }
        defer { session.stop() }

        let url = try XCTUnwrap(session.streamURL)
        let port = try XCTUnwrap(UInt16(url.split(separator: ":").last?.split(separator: "/").first ?? ""))
        let viewer = try connectLoopback(port: port)
        viewer.setTimeouts(seconds: 3)
        try viewer.write(Data("GET /live.ts HTTP/1.1\r\n\r\n".utf8))

        var received = Data()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, let chunk = try? viewer.readSome(limit: 1 << 20) { received.append(chunk) }

        let headerEnd = try XCTUnwrap(received.range(of: Data("\r\n\r\n".utf8)))
        var body = Data(received[headerEnd.upperBound...])
        body.removeLast(body.count % 188)
        let file = workDirectory.appendingPathComponent("hevc.ts")
        try body.write(to: file)

        let probe = try runTool("ffprobe", ["-v", "error", "-show_streams", "-of", "json", file.path])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(probe.output.utf8)) as? [String: Any])
        let streams = try XCTUnwrap(json["streams"] as? [[String: Any]])
        let names = streams.compactMap { $0["codec_name"] as? String }
        print("DEVICE>> hevc streams=\(names) bytes=\(body.count)")
        XCTAssertEqual(names.first, "hevc")
        let decode = try runTool("ffmpeg", ["-v", "error", "-i", file.path, "-map", "0:v:0", "-f", "null", "-"])
        print("DEVICE>> hevc ffmpeg status=\(decode.status) errors=\(decode.errors.debugDescription)")
        XCTAssertEqual(decode.status, 0)
    }

    // MARK: Recording and screenshot

    func testRecordingProducesAPlayableMP4WithAudio() async throws {
        let (session, events) = try await startSession()
        defer { session.stop() }
        try await pause(1.0)

        let url = workDirectory.appendingPathComponent("recording.mp4")
        try session.startRecording(to: url)
        // Some motion so frames keep coming.
        session.send(.expandNotificationPanel)
        try await pause(1.5)
        session.send(.collapsePanels)
        try await pause(2.0)
        let saved = try await session.stopRecording()
        XCTAssertEqual(saved, url)

        let probe = try runTool("ffprobe", ["-v", "error", "-show_streams", "-show_format", "-of", "json", url.path])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(probe.output.utf8)) as? [String: Any])
        let streams = try XCTUnwrap(json["streams"] as? [[String: Any]])
        let video = try XCTUnwrap(streams.first { $0["codec_type"] as? String == "video" })
        let duration = Double((json["format"] as? [String: Any])?["duration"] as? String ?? "") ?? 0
        print("DEVICE>> recording streams=\(streams.compactMap { $0["codec_name"] as? String }) duration=\(duration) size=\((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) ?? 0)")
        XCTAssertEqual(video["codec_name"] as? String, "h264")
        XCTAssertEqual(video["width"] as? Int, 1080)
        XCTAssertEqual(video["height"] as? Int, 2340)
        XCTAssertGreaterThan(duration, 2.5)
        if !events.audioUnavailable {
            XCTAssertTrue(streams.contains { $0["codec_type"] as? String == "audio" }, "recording has no audio track")
        }
        // Decode every frame with the file's own timebase. ffmpeg's `null` output otherwise rounds frame times to a 1/60 s grid
        // and warns about "non monotonically increasing dts" when two real frames land less than 1/60 s apart.
        let decode = try runTool("ffmpeg", ["-v", "error", "-i", url.path, "-fps_mode", "passthrough", "-enc_time_base", "-1", "-f", "null", "-"])
        // What matters about the file itself: video timestamps strictly increase.
        let packets = try runTool("ffprobe", ["-v", "error", "-select_streams", "v", "-show_entries", "packet=dts", "-of", "csv=p=0", url.path])
        let stamps = packets.output.split(whereSeparator: \.isNewline).compactMap { Int($0) }
        XCTAssertGreaterThan(stamps.count, 10)
        XCTAssertTrue(zip(stamps, stamps.dropFirst()).allSatisfy { $0 < $1 }, "video dts must strictly increase in the saved file")
        XCTAssertEqual(decode.status, 0)
        XCTAssertEqual(decode.errors, "")
    }

    func testScreenshotIsAFullResolutionPNG() throws {
        let png = try adb.run(["-s", serial, "exec-out", "screencap", "-p"], timeout: 15)
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(png.readBigEndian(UInt32.self, at: 16), 1080)
        XCTAssertEqual(png.readBigEndian(UInt32.self, at: 20), 2340)
    }

    // MARK: Developer tools

    func testLogcatStreamsLines() async throws {
        let logcat = await LogcatModel()
        await logcat.start(adb: adb, serial: serial)
        try await pause(2.5)
        let count = await logcat.entries.count
        let running = await logcat.isRunning
        let sample = await logcat.entries.last?.text ?? ""
        print("DEVICE>> logcat lines=\(count) sample=\(sample.prefix(100))")
        await logcat.stop()
        XCTAssertTrue(running)
        XCTAssertGreaterThan(count, 5)
    }

    @MainActor
    func testAppModelActionsRunAgainstThePhone() async throws {
        let originalNight = try shell(["cmd", "uimode", "night"]) // "Night mode: yes"
        let originalAnimation = try shell(["settings", "get", "global", "window_animation_scale"])
        let originalPointer = try shell(["settings", "get", "system", "pointer_location"])
        defer { // always put the phone back exactly as it was
            let mode = originalNight.contains("yes") ? "yes" : originalNight.contains("no") ? "no" : "auto"
            _ = try? shell(["cmd", "uimode", "night", mode])
            for key in ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"] {
                _ = try? shell(["settings", "put", "global", key, originalAnimation])
            }
            _ = try? shell(["settings", "put", "system", "pointer_location", originalPointer == "null" ? "0" : originalPointer])
        }

        let model = AppModel()
        model.selectedSerial = serial

        // Device tools.
        model.run(.darkModeOff)
        try await pause(1.5)
        XCTAssertTrue(try shell(["cmd", "uimode", "night"]).contains("no"))
        model.run(.darkModeOn)
        try await pause(1.5)
        XCTAssertTrue(try shell(["cmd", "uimode", "night"]).contains("yes"))

        model.run(.animationsOff)
        try await pause(1.5)
        XCTAssertEqual(try shell(["settings", "get", "global", "window_animation_scale"]), "0")
        model.run(.animationsOn)
        try await pause(1.5)
        XCTAssertEqual(try shell(["settings", "get", "global", "window_animation_scale"]), "1")

        model.run(.pointerLocationOn)
        try await pause(1.2)
        XCTAssertEqual(try shell(["settings", "get", "system", "pointer_location"]), "1")
        model.run(.pointerLocationOff)
        try await pause(1.2)
        XCTAssertEqual(try shell(["settings", "get", "system", "pointer_location"]), "0")

        // Drag & drop of a non-APK file copies it to Download (and the name is sanitized).
        let local = workDirectory.appendingPathComponent("benzmirror drop;test.txt")
        try Data("hello from the mac".utf8).write(to: local)
        model.handleDrop([local])
        try await pause(2.5)
        let remote = "/sdcard/Download/benzmirror drop_test.txt"
        let pushed = try shell(["cat", "'\(remote)'"])
        _ = try? shell(["rm", "-f", "'\(remote)'"])
        print("DEVICE>> push notice=\(model.notice ?? "nil") content=\(pushed)")
        XCTAssertEqual(pushed, "hello from the mac")

        // Dropping a folder is refused.
        model.handleDrop([workDirectory])
        XCTAssertEqual(model.notice, "Folders cannot be copied to the phone")
    }

    // MARK: Foreground app

    @MainActor
    func testForegroundAppFollowsWhatIsOnThePhone() async throws {
        let detector = ForegroundAppDetector()
        detector.start(interval: .milliseconds(300), fetch: ForegroundAppDetector.fetcher(adb: adb, serial: serial))
        defer {
            detector.stop()
            _ = try? shell(["input", "keyevent", "KEYCODE_HOME"])
        }

        func waitFor(_ package: String) async throws -> Bool {
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if detector.current?.package == package { return true }
                try await Task.sleep(for: .milliseconds(150))
            }
            return false
        }

        _ = try shell(["input", "keyevent", "KEYCODE_HOME"])
        let home = detector.current
        let launcherFound = try await waitFor("com.sec.android.app.launcher")
        print("DEVICE>> foreground home=\(String(describing: detector.current?.package)) before=\(String(describing: home?.package))")
        XCTAssertTrue(launcherFound, "launcher not detected: \(String(describing: detector.current))")

        _ = try shell(["am", "start", "-a", "android.settings.SETTINGS"])
        let settingsFound = try await waitFor("com.android.settings")
        print("DEVICE>> foreground settings=\(String(describing: detector.current))")
        XCTAssertTrue(settingsFound, "Settings not detected: \(String(describing: detector.current))")

        // A system window over the app must not change the answer.
        _ = try shell(["cmd", "statusbar", "expand-notifications"])
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(detector.current?.package, "com.android.settings", "the notification shade must not hide the app")
        _ = try shell(["cmd", "statusbar", "collapse"])
    }

    func testDeviceInfoMatchesThePhone() throws {
        let info = try DeviceInfo.fetch(adb: adb, serial: serial)
        print("DEVICE>> info=\(info)")
        XCTAssertEqual(info.screenSize, CGSize(width: 1080, height: 2340))
        XCTAssertEqual(info.density, 480)
        XCTAssertEqual(info.manufacturer.lowercased(), "samsung")
        XCTAssertGreaterThanOrEqual(info.sdk, 30)
        XCTAssertEqual(info.dp(fromPixels: 1080), 360, "matches the sw360dp the phone reports")
    }

    // MARK: App model and several phones

    @MainActor
    private func waitUntil(_ description: String, timeout: Double = 15, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out waiting for: \(description)") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @MainActor
    func testAppModelMirrorsOnePhoneThenDisconnects() async throws {
        let model = AppModel()
        model.selectedSerial = serial
        try await waitUntil("the phone is listed") { model.selectedDevice?.isReady == true }

        model.connect()
        try await waitUntil("mirroring starts") { model.isMirroring }
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.activeSerial, serial)
        XCTAssertEqual(model.state, .mirroring)
        XCTAssertEqual(model.deviceName, "SM-S911B")

        try await waitUntil("details arrive", timeout: 10) {
            model.deviceInfo != nil && model.foreground.current != nil && model.stats.framesPerSecond > 0
        }
        print("DEVICE>> model deviceInfo=\(model.deviceInfo?.model ?? "-") app=\(model.foreground.current?.package ?? "-") fps=\(model.stats.framesPerSecond)")
        XCTAssertEqual(model.videoSize.height, 1920, "the default Balanced preset caps the long edge at 1920")

        model.isAddingDevice = true
        XCTAssertEqual(model.state, .idle, "the connect screen shows while adding a phone")
        model.activate(serial)
        XCTAssertEqual(model.state, .mirroring)

        model.disconnect()
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.active)
    }

    /// The same phone reached over USB and over Wi-Fi counts as two devices, so it exercises two sessions at once.
    @MainActor
    func testTwoSessionsRunAtOnce() async throws {
        guard ProcessInfo.processInfo.environment["BENZMIRROR_TEST_WIRELESS"] == "1" else {
            throw XCTSkip("Set BENZMIRROR_TEST_WIRELESS=1 (needs the Mac on the phone's network)")
        }
        let address = try adb.enableWireless(serial: serial)
        defer {
            _ = try? adb.run(["-s", address, "usb"], timeout: 10)
            _ = try? adb.run(["disconnect", address], timeout: 10)
        }

        let model = AppModel()
        model.settings.obsStreamEnabled = true
        model.settings.obsStreamPort = 38_765
        try await waitUntil("both transports are listed") {
            model.devices.contains { $0.serial == self.serial && $0.isReady } && model.devices.contains { $0.serial == address && $0.isReady }
        }

        model.selectedSerial = serial
        model.connect()
        try await waitUntil("first phone mirrors") { model.sessions.count == 1 && model.isMirroring }
        model.selectedSerial = address
        model.connect()
        try await waitUntil("second phone mirrors", timeout: 20) { model.sessions.count == 2 && model.active?.state == .mirroring }

        XCTAssertEqual(model.activeSerial, address, "the newest phone comes to the front")
        let urls = model.sessions.compactMap(\.streamURL)
        XCTAssertEqual(Set(urls).count, 2, "each phone needs its own OBS port: \(urls)")

        try await Task.sleep(for: .seconds(3))
        let rates = model.sessions.map { "\($0.serial): \(String(format: "%.1f", $0.stats.framesPerSecond)) fps" }
        print("DEVICE>> two sessions urls=\(urls) \(rates)")
        for session in model.sessions { XCTAssertGreaterThan(session.stats.framesPerSecond, 1, session.serial) }

        model.activate(serial)
        XCTAssertEqual(model.activeSerial, serial)
        model.disconnect()
        XCTAssertEqual(model.sessions.count, 1)
        XCTAssertEqual(model.activeSerial, address, "falls back to the remaining phone")
        model.disconnect()
        XCTAssertTrue(model.sessions.isEmpty)
    }

    // MARK: Keymap

    /// The centre of Settings' search field as a fraction of the screen, found with uiautomator.
    private func settingsSearchFieldRatio() throws -> NormalizedPoint {
        _ = try shell(["am", "start", "-a", "android.settings.SETTINGS"])
        Thread.sleep(forTimeInterval: 2)
        _ = try shell(["uiautomator", "dump", "/sdcard/benz-ui.xml"])
        let xml = try shell(["cat", "/sdcard/benz-ui.xml"])
        _ = try? shell(["rm", "-f", "/sdcard/benz-ui.xml"])

        let pattern = #"resource-id="com\.android\.settings:id/search_plate"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]""#
        let match = try XCTUnwrap(try NSRegularExpression(pattern: pattern).firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
                                  "Settings search field not found")
        let values = (1...4).map { Double(xml[Range(match.range(at: $0), in: xml)!])! }
        return NormalizedPoint(x: (values[0] + values[2]) / 2 / 1080, y: (values[1] + values[3]) / 2 / 2340)
    }

    @MainActor
    func testKeymapKeyPressTapsThePhonesScreen() async throws {
        let target = try settingsSearchFieldRatio()
        defer { // leave the phone on its home screen
            for _ in 0..<2 { _ = try? shell(["input", "keyevent", "KEYCODE_BACK"]) }
            _ = try? shell(["input", "keyevent", "KEYCODE_HOME"])
        }

        let root = workDirectory.appendingPathComponent("keymaps")
        let model = AppModel(keymapRoot: root)
        model.selectedSerial = serial
        try await waitUntil("the phone is listed") { model.selectedDevice?.isReady == true }
        model.connect()
        try await waitUntil("mirroring starts") { model.isMirroring }

        let keymap = Keymap(elements: [KeymapElement(label: "Search", position: target, action: .button(key: 12, mode: .tap))])
        try XCTUnwrap(model.keymapStore).save(Profile(id: "live.test", name: "Live test", payload: keymap))
        model.refreshKeymaps()
        XCTAssertEqual(model.keymapProfiles.map(\.id), ["live.test"])

        model.setKeymapEnabled(true)
        XCTAssertFalse(model.isKeymapEnabled, "cannot switch on before a keymap is chosen")
        model.loadKeymap(id: "live.test")
        model.setKeymapEnabled(true)
        XCTAssertTrue(model.isKeymapEnabled)
        XCTAssertEqual(model.currentKeymap?.name, "Live test")

        try await Task.sleep(for: .milliseconds(500))
        let before = try screenshotDigest()
        let keymapController = try XCTUnwrap(model.active?.keymap)
        XCTAssertFalse(keymapController.keyDown(0), "an unbound key is left for normal typing")
        XCTAssertTrue(keymapController.keyDown(12))
        XCTAssertTrue(keymapController.keyUp(12))
        try await Task.sleep(for: .seconds(1.5))
        let after = try screenshotDigest()
        print("DEVICE>> keymap tapped ratio=(\(target.x), \(target.y)) screenChanged=\(before != after)")
        XCTAssertNotEqual(before, after, "the keymap tap did not reach the phone")

        model.setKeymapEnabled(false)
        XCTAssertFalse(keymapController.keyDown(12), "a switched-off keymap does not consume keys")
        model.disconnect()
    }

    @MainActor
    func testKeymapJoystickDragsThePhonesScreen() async throws {
        defer {
            _ = try? shell(["input", "keyevent", "KEYCODE_BACK"])
            _ = try? shell(["input", "keyevent", "KEYCODE_HOME"])
        }
        _ = try shell(["input", "keyevent", "KEYCODE_HOME"])
        try await Task.sleep(for: .seconds(1))

        let model = AppModel(keymapRoot: workDirectory.appendingPathComponent("keymaps"))
        model.selectedSerial = serial
        try await waitUntil("the phone is listed") { model.selectedDevice?.isReady == true }
        model.connect()
        try await waitUntil("mirroring starts") { model.isMirroring }

        // A stick centred on the top edge with a long reach: holding "down" drags a finger from the status bar
        // downwards, which pulls the notification shade open.
        let stick = KeymapElement(label: "Pull", position: NormalizedPoint(x: 0.5, y: 0.004),
                                  action: .joystick(up: 13, left: 0, down: 1, right: 2, radius: 0.4, response: 0.15))
        try XCTUnwrap(model.keymapStore).save(Profile(id: "live.stick", name: "Live stick", payload: Keymap(elements: [stick])))
        model.refreshKeymaps()
        model.loadKeymap(id: "live.stick")
        model.setKeymapEnabled(true)

        let controller = try XCTUnwrap(model.active?.keymap)
        let home = try screenshotDigest()
        XCTAssertTrue(controller.keyDown(1))
        try await Task.sleep(for: .seconds(1.2)) // eases down over ~0.15 s, then holds
        let pulled = try screenshotDigest()
        XCTAssertTrue(controller.keyUp(1))
        try await Task.sleep(for: .seconds(0.8))
        print("DEVICE>> joystick screenChanged=\(home != pulled)")
        XCTAssertNotEqual(home, pulled, "dragging the stick down did not pull the shade")

        model.disconnect()
    }

    @MainActor
    func testKeymapFreeLookMovesAFingerOnThePhone() async throws {
        defer {
            _ = try? shell(["input", "keyevent", "KEYCODE_BACK"])
            _ = try? shell(["input", "keyevent", "KEYCODE_HOME"])
        }
        _ = try shell(["input", "keyevent", "KEYCODE_HOME"])
        try await Task.sleep(for: .seconds(1))

        let cursor = FakeCursorCapture() // never lock the real pointer in a test
        let model = AppModel(keymapRoot: workDirectory.appendingPathComponent("keymaps"), cursorCapture: cursor)
        model.selectedSerial = serial
        try await waitUntil("the phone is listed") { model.selectedDevice?.isReady == true }
        model.connect()
        try await waitUntil("mirroring starts") { model.isMirroring }

        // The look area sits on the top edge, so moving the mouse down drags a finger down from the status bar.
        let look = KeymapElement(label: "Look", position: NormalizedPoint(x: 0.5, y: 0.004),
                                 action: .aim(toggleKey: 50, sensitivity: 2, radius: 0.4))
        try XCTUnwrap(model.keymapStore).save(Profile(id: "live.aim", name: "Live aim", payload: Keymap(elements: [look])))
        model.refreshKeymaps()
        model.loadKeymap(id: "live.aim")
        model.setKeymapEnabled(true)

        let controller = try XCTUnwrap(model.active?.keymap)
        let home = try screenshotDigest()
        XCTAssertFalse(controller.mouseMoved(deltaX: 0, deltaY: 40), "not aiming yet: the mouse is a normal mouse")

        XCTAssertTrue(controller.keyDown(50)) // the toggle key
        XCTAssertTrue(controller.isAiming)
        XCTAssertTrue(cursor.isCaptured)
        for _ in 0..<5 { // 5 x 40 points x 2 px = 400 px of the 432 px reach
            XCTAssertTrue(controller.mouseMoved(deltaX: 0, deltaY: 40))
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(900))
        let pulled = try screenshotDigest()
        print("DEVICE>> free-look screenChanged=\(home != pulled) pointerCaptured=\(cursor.isCaptured)")
        XCTAssertNotEqual(home, pulled, "moving the mouse did not drag the finger")

        _ = controller.keyUp(50)
        XCTAssertTrue(controller.keyDown(50)) // toggle off
        XCTAssertFalse(controller.isAiming)
        XCTAssertFalse(cursor.isCaptured, "the pointer is released when free-look ends")
        XCTAssertEqual(cursor.history, [true, false])

        model.disconnect()
        XCTAssertFalse(cursor.isCaptured)
    }

    @MainActor
    func testKeymapSkillShotDragsAFingerTowardsTheMouse() async throws {
        defer {
            _ = try? shell(["input", "keyevent", "KEYCODE_BACK"])
            _ = try? shell(["input", "keyevent", "KEYCODE_HOME"])
        }
        _ = try shell(["input", "keyevent", "KEYCODE_HOME"])
        try await Task.sleep(for: .seconds(1))

        let model = AppModel(keymapRoot: workDirectory.appendingPathComponent("keymaps"), cursorCapture: FakeCursorCapture())
        model.selectedSerial = serial
        try await waitUntil("the phone is listed") { model.selectedDevice?.isReady == true }
        model.connect()
        try await waitUntil("mirroring starts") { model.isMirroring }

        // The skill button sits on the top edge and the hero just below it: a mouse further down makes the
        // finger drag downwards, which pulls the notification shade open.
        let skill = KeymapElement(label: "Pull", position: NormalizedPoint(x: 0.5, y: 0.004),
                                  action: .skillShot(key: 12, cast: .onRelease, radius: 0.4, range: 0.2, hero: NormalizedPoint(x: 0.5, y: 0.05)))
        try XCTUnwrap(model.keymapStore).save(Profile(id: "live.skill", name: "Live skill", payload: Keymap(elements: [skill])))
        model.refreshKeymaps()
        model.loadKeymap(id: "live.skill")
        model.setKeymapEnabled(true)

        let controller = try XCTUnwrap(model.active?.keymap)
        let home = try screenshotDigest()
        XCTAssertTrue(controller.keyDown(12)) // finger down on the button
        for step in 1...6 { // the mouse glides down the screen
            controller.pointerMoved(to: CGPoint(x: 0.5, y: 0.05 + 0.025 * Double(step)))
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .milliseconds(900))
        let aimed = try screenshotDigest()
        XCTAssertTrue(controller.keyUp(12)) // cast: the finger lifts
        try await Task.sleep(for: .milliseconds(500))
        print("DEVICE>> skill-shot screenChanged=\(home != aimed)")
        XCTAssertNotEqual(home, aimed, "aiming the skill did not drag the finger")

        model.disconnect()
    }

    @MainActor
    func testRecordedMacroPlaysBackOnThePhone() async throws {
        defer {
            _ = try? shell(["input", "keyevent", "KEYCODE_BACK"])
            _ = try? shell(["input", "keyevent", "KEYCODE_HOME"])
        }
        _ = try shell(["input", "keyevent", "KEYCODE_HOME"])
        try await Task.sleep(for: .seconds(1))

        let model = AppModel(keymapRoot: workDirectory.appendingPathComponent("keymaps"), cursorCapture: FakeCursorCapture())
        model.selectedSerial = serial
        try await waitUntil("the phone is listed") { model.selectedDevice?.isReady == true }
        model.connect()
        try await waitUntil("mirroring starts") { model.isMirroring }
        let phone = try XCTUnwrap(model.active)
        let size = model.videoSize
        let width = UInt16(size.width), height = UInt16(size.height)

        // 1. Record: swipe down from the top edge, the way the mouse would.
        let before = try screenshotDigest()
        phone.startMacroRecording()
        XCTAssertTrue(model.isRecordingMacro)
        func touch(_ action: TouchAction, y: Int32) {
            phone.scrcpy.send(.touch(action, TouchPosition(x: Int32(width / 2), y: y, frameWidth: width, frameHeight: height),
                                     pressure: action == .up ? 0 : 1, pointer: .mouse))
        }
        touch(.down, y: 4)
        for step in 1...20 {
            touch(.move, y: Int32(4 + step * Int(height) / 50))
            try await Task.sleep(for: .milliseconds(15))
        }
        touch(.up, y: Int32(4 + 20 * Int(height) / 50))
        let steps = phone.stopMacroRecording()
        XCTAssertFalse(model.isRecordingMacro)
        XCTAssertEqual(steps.first?.kind, .down)
        XCTAssertEqual(steps.last?.kind, .up)
        XCTAssertGreaterThan(steps.count, 15)
        XCTAssertGreaterThan(steps.last?.time ?? 0, 0.2, "the recording kept the timing")
        try await Task.sleep(for: .milliseconds(900))
        let opened = try screenshotDigest()
        XCTAssertNotEqual(before, opened, "the live swipe should have opened the shade")

        // 2. Close the shade again.
        _ = try shell(["input", "keyevent", "KEYCODE_BACK"])
        try await Task.sleep(for: .seconds(1))
        let closed = try screenshotDigest()

        // 3. Save the recording on the Q key, switch the keymap on, and play it.
        model.saveMacro(steps, key: 12)
        XCTAssertEqual(model.currentKeymap?.id, "macros")
        let saved = try XCTUnwrap(model.keymapStore).load(id: "macros").payload
        XCTAssertEqual(saved.elements.count, 1)
        XCTAssertEqual(saved.elements[0].keys, [12])
        model.setKeymapEnabled(true)
        XCTAssertTrue(model.isKeymapEnabled)

        let controller = phone.keymap
        XCTAssertTrue(controller.keyDown(12))
        try await Task.sleep(for: .seconds(1.8))
        let replayed = try screenshotDigest()
        print("DEVICE>> macro steps=\(steps.count) duration=\(steps.last?.time ?? 0) replayOpenedShade=\(closed != replayed)")
        XCTAssertNotEqual(closed, replayed, "playing the macro did not open the shade")
        _ = controller.keyUp(12)

        model.disconnect()
    }

    @MainActor
    func testKeymapEditorFlowThroughTheAppModel() async throws {
        let model = AppModel(keymapRoot: workDirectory.appendingPathComponent("keymaps"), cursorCapture: FakeCursorCapture())
        model.selectedSerial = serial
        try await waitUntil("the phone is listed") { model.selectedDevice?.isReady == true }
        model.connect()
        try await waitUntil("mirroring starts") { model.isMirroring }
        let controller = try XCTUnwrap(model.active?.keymap)

        // Open the editor: the keymap is off and keys stop reaching the phone.
        model.startEditingKeymap()
        let editor = try XCTUnwrap(model.editor)
        XCTAssertTrue(controller.isEditing)
        XCTAssertFalse(controller.isEnabled)

        editor.name = "Live editor"
        let button = editor.add(.button)
        editor.update(button) { $0.action = .button(key: 12, mode: .tap) }
        editor.add(.joystick)

        // A keymap that cannot be saved keeps the editor open and says why.
        let stick = try XCTUnwrap(editor.keymap.elements.last)
        editor.update(stick.id) { $0.action = .joystick(up: 13, left: 13, down: 1, right: 2, radius: 0.1, response: 0.1) }
        model.closeEditor(save: true)
        XCTAssertNotNil(model.editor, "stays open when the save fails")
        XCTAssertTrue(model.editorMessage?.contains("four different keys") == true, model.editorMessage ?? "nil")
        XCTAssertTrue(model.keymapProfiles.isEmpty)

        // Fix it and save: the profile exists, is loaded into the phone's keymap, and the editor closes.
        editor.update(stick.id) { $0.action = .joystick(up: 13, left: 0, down: 1, right: 2, radius: 0.1, response: 0.1) }
        model.closeEditor(save: true)
        XCTAssertNil(model.editor)
        XCTAssertNil(model.editorMessage)
        XCTAssertFalse(controller.isEditing)
        XCTAssertEqual(model.keymapProfiles.map(\.name), ["Live editor"])
        XCTAssertEqual(model.currentKeymap?.name, "Live editor")
        XCTAssertTrue(controller.hasKeymap)

        // The saved keymap works.
        model.setKeymapEnabled(true)
        XCTAssertTrue(controller.handles(12))
        XCTAssertTrue(controller.handles(13))
        model.setKeymapEnabled(false)

        // Opening it again edits the same profile; discarding changes nothing.
        model.startEditingKeymap()
        let again = try XCTUnwrap(model.editor)
        XCTAssertEqual(again.profileID, model.currentKeymap?.id)
        XCTAssertEqual(again.keymap.elements.count, 2)
        again.delete(again.keymap.elements[0].id)
        model.closeEditor(save: false)
        XCTAssertEqual(try XCTUnwrap(model.keymapStore).load(id: try XCTUnwrap(again.profileID)).payload.elements.count, 2)

        model.disconnect()
        XCTAssertNil(model.editor)
    }

    @MainActor
    func testKeymapSwitchesByItselfWhenTheGameOpensOnThePhone() async throws {
        defer { _ = try? shell(["input", "keyevent", "KEYCODE_HOME"]) }
        _ = try shell(["input", "keyevent", "KEYCODE_HOME"])
        try await Task.sleep(for: .seconds(1))

        let model = AppModel(keymapRoot: workDirectory.appendingPathComponent("keymaps"), cursorCapture: FakeCursorCapture())
        // Two keymaps, each for a different "game". Settings and the Clock stand in for games.
        let store = try XCTUnwrap(model.keymapStore)
        try store.save(Profile(id: "settings-keys", name: "Settings keys", payload: Keymap(package: "com.android.settings")))
        try store.save(Profile(id: "no-package", name: "Unrelated", payload: Keymap()))
        model.refreshKeymaps()
        XCTAssertEqual(model.keymapPackageIndex, ["com.android.settings": "settings-keys"])

        model.selectedSerial = serial
        try await waitUntil("the phone is listed") { model.selectedDevice?.isReady == true }
        model.connect()
        try await waitUntil("mirroring starts") { model.isMirroring }
        let phone = try XCTUnwrap(model.active)
        XCTAssertFalse(phone.keymap.isEnabled)

        // The "game" opens: its keymap loads and switches on.
        _ = try shell(["am", "start", "-a", "android.settings.SETTINGS"])
        try await waitUntil("the keymap switches on by itself", timeout: 15) { phone.keymap.isEnabled }
        XCTAssertEqual(phone.keymap.profile?.id, "settings-keys")
        XCTAssertTrue(phone.keymap.hasKeymap)

        // Back to the home screen: the keymap the app switched on is switched off again.
        _ = try shell(["input", "keyevent", "KEYCODE_HOME"])
        try await waitUntil("the keymap switches off when the game closes", timeout: 15) { !phone.keymap.isEnabled }
        XCTAssertEqual(phone.keymap.profile?.id, "settings-keys", "it stays loaded")
        print("DEVICE>> auto keymap: on in Settings, off on the home screen")

        model.disconnect()
    }

    @MainActor
    func testLogcatFollowsTheAppInFrontAndFlagsItsCrash() async throws {
        defer {
            _ = try? shell(["am", "force-stop", "com.android.settings"])
            _ = try? shell(["input", "keyevent", "KEYCODE_HOME"])
        }
        _ = try shell(["am", "start", "-a", "android.settings.SETTINGS"])
        try await Task.sleep(for: .seconds(2))
        let launcherPIDs = ProcessList.pids(of: "com.sec.android.app.launcher", in: ProcessList.parse(try shell([ProcessList.command])))
        XCTAssertFalse(launcherPIDs.isEmpty)

        let logcat = LogcatModel()
        logcat.start(adb: adb, serial: serial)
        defer { logcat.stop() }
        logcat.setForegroundPackage("com.android.settings")
        try await waitUntil("the app's processes are known") { logcat.knownProcessCount > 0 }

        // Crash the app in front (the shell may report a permission problem for a second user; the crash still happens).
        _ = try? shell(["am", "crash", "com.android.settings"])
        try await waitUntil("the crash is flagged", timeout: 20) { !logcat.crashIDs.isEmpty }
        try await waitUntil("the system's note that the process died arrives", timeout: 10) { logcat.entries.contains { $0.kind == .processDied } }

        let header = try XCTUnwrap(logcat.entries.first { $0.id == logcat.crashIDs[0] })
        XCTAssertEqual(header.kind, .crash)
        XCTAssertTrue(header.message.hasPrefix("FATAL EXCEPTION"))
        let block = logcat.entries.filter { $0.crashBlock == header.crashBlock }
        XCTAssertTrue(block.contains { $0.kind == .exception }, "the exception line is part of the block")
        XCTAssertGreaterThan(block.filter { $0.kind == .stackFrame }.count, 3, "and its stack frames")
        XCTAssertTrue(block.contains { $0.message.contains("Process: com.android.settings") })

        XCTAssertGreaterThan(logcat.entries.count, 5)
        // Lines of another process (the launcher, say) are kept only when they mention the app, as system notes about it do.
        let others = logcat.entries.filter { $0.pid.map(launcherPIDs.contains) == true }
        XCTAssertTrue(others.allSatisfy { $0.message.contains("com.android.settings") }, "a line of another app leaked through")
        print("DEVICE>> logcat scoped to Settings: kept=\(logcat.entries.count) crashes=\(logcat.crashIDs.count) blockLines=\(block.count)")
    }

    // MARK: Wireless

    func testWirelessRefusesWhenPhoneAndMacAreOnDifferentNetworks() throws {
        let elsewhere = IPv4Interface(name: "en0", address: 0xC0A8_0105, prefix: 24) // 192.168.1.5
        XCTAssertThrowsError(try adb.enableWireless(serial: serial, macNetworks: [elsewhere])) { error in
            XCTAssertTrue(error.localizedDescription.contains("same network"), error.localizedDescription)
        }
        XCTAssertThrowsError(try adb.connect(address: "10.255.255.1:5555")) // unreachable, must fail cleanly
    }

    /// Drives the shade open and closed for a few seconds so the encoder has real motion, then reports the rates.
    private func measureUnderMotion(_ session: ScrcpySession) async throws -> StreamStatistics.Snapshot {
        _ = session.statistics.snapshot() // start a clean window
        for _ in 0..<5 {
            session.send(.expandNotificationPanel)
            try await pause(0.6)
            session.send(.collapsePanels)
            try await pause(0.6)
        }
        return session.statistics.snapshot()
    }

    /// Needs the Mac on the phone's network (for example its hotspot). Opt-in because it briefly puts adbd in
    /// TCP mode; the test switches the phone back to USB mode afterwards.
    func testWirelessAdbWorksOverThePhonesNetwork() async throws {
        guard ProcessInfo.processInfo.environment["BENZMIRROR_TEST_WIRELESS"] == "1" else {
            throw XCTSkip("Set BENZMIRROR_TEST_WIRELESS=1 to switch the phone to wireless adb")
        }

        let usb = try await startSession()
        let usbRates = try await measureUnderMotion(usb.0)
        usb.0.stop()
        try await pause(1)

        let address = try adb.enableWireless(serial: serial)
        defer {
            _ = try? adb.run(["-s", address, "usb"], timeout: 10) // back to USB mode
            _ = try? adb.run(["disconnect", address], timeout: 10)
        }
        XCTAssertTrue(try adb.devices().contains { $0.serial == address && $0.isReady }, "wireless device not listed")

        let started = Date()
        let (session, events) = try await startSession(serial: address)
        let startup = Date().timeIntervalSince(started)
        defer { session.stop() }
        let wifiRates = try await measureUnderMotion(session)

        print("DEVICE>> wireless address=\(address) startup=\(String(format: "%.2f", startup))s")
        print("DEVICE>> under motion  USB: \(String(format: "%.1f", usbRates.framesPerSecond)) fps \(String(format: "%.1f", usbRates.megabitsPerSecond)) Mbps   Wi-Fi: \(String(format: "%.1f", wifiRates.framesPerSecond)) fps \(String(format: "%.1f", wifiRates.megabitsPerSecond)) Mbps")
        XCTAssertFalse(events.ended)
        XCTAssertGreaterThan(wifiRates.framesPerSecond, 5)
    }
}

// MARK: - UI inspector (real phone)

extension DeviceFeatureTests {
    func testInspectorReadsTheRealScreenAndMeasuresIt() async throws {
        _ = try shell(["input", "keyevent", "KEYCODE_HOME"])
        try await Task.sleep(for: .seconds(1))
        let data = try adb.run(["-s", serial, "exec-out", UIHierarchyParser.command], timeout: 20)
        let hierarchy = try XCTUnwrap(UIHierarchyParser.parse(data), "The phone's dump could not be read")
        XCTAssertGreaterThan(hierarchy.nodes.count, 3)

        let info = try DeviceInfo.fetch(adb: adb, serial: serial)
        let screen = try XCTUnwrap(hierarchy.screenSize)
        XCTAssertEqual(screen, info.screenSize(matching: screen), "The dump's root must cover the whole screen")

        // Every element must lie on the screen, and the center of the screen must resolve to something inside it.
        let full = CGRect(origin: .zero, size: screen).insetBy(dx: -2, dy: -2)
        for node in hierarchy.nodes { XCTAssertTrue(full.contains(node.bounds), "\(node.className) \(node.bounds) leaves the screen") }
        let hit = try XCTUnwrap(hierarchy.node(atRatio: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertTrue(hit.bounds.contains(CGPoint(x: screen.width / 2, y: screen.height / 2)))
        let measured = NodeMeasurements(node: hit, densityScale: info.densityScale)
        XCTAssertNotNil(measured.dpText)
    }
}

// MARK: - Real phone

extension DeviceFeatureTests {
    func testDesignToolsReadTheRealScreen() async throws {
        _ = try shell(["input", "keyevent", "KEYCODE_HOME"])
        try await Task.sleep(for: .seconds(1))
        let png = try await DesignModel.fetcher(adb: adb, serial: serial)()
        let image = try XCTUnwrap(PixelImage(png: png), "screencap did not give a readable picture")
        let info = try DeviceInfo.fetch(adb: adb, serial: serial)
        XCTAssertEqual(CGSize(width: image.width, height: image.height), info.screenSize(matching: CGSize(width: image.width, height: image.height)),
                       "The still must be the phone's real screen size")
        XCTAssertNotNil(image.color(atRatio: CGPoint(x: 0.5, y: 0.5)))
        let readout = try XCTUnwrap(CrosshairReadout(ratio: CGPoint(x: 0.5, y: 0.5), screenSize: info.screenSize(matching: CGSize(width: image.width, height: image.height)),
                                                     densityScale: info.densityScale))
        XCTAssertNotNil(readout.dpText)
    }
}
