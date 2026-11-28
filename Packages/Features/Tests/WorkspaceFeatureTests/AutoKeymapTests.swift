import XCTest
import FeatureTestSupport
@testable import DomainModels
@testable import Networking
@testable import Persistence
@testable import WorkspaceFeature

final class KeymapAutoSwitchRulesTests: XCTestCase {
    private let index = ["com.game.one": "one", "com.game.two": "two"]

    private func actions(_ package: String?, loaded: String? = nil, enabled: Bool = false, auto: Bool = false, enables: Bool = true) -> [KeymapAutoSwitch.Action] {
        KeymapAutoSwitch.actions(foreground: package, index: index, loadedProfileID: loaded, isEnabled: enabled,
                                 wasAutoEnabled: auto, enablesAutomatically: enables)
    }

    func testAGameWithAKeymapLoadsAndSwitchesItOn() {
        XCTAssertEqual(actions("com.game.one"), [.load("one"), .enable])
    }

    func testAnAlreadyLoadedKeymapIsOnlySwitchedOn() {
        XCTAssertEqual(actions("com.game.one", loaded: "one"), [.enable])
    }

    func testNothingIsDoneWhenItIsAlreadyLoadedAndOn() {
        XCTAssertEqual(actions("com.game.one", loaded: "one", enabled: true), [])
    }

    func testAnotherGameSwapsTheKeymap() {
        XCTAssertEqual(actions("com.game.two", loaded: "one", enabled: true, auto: true), [.load("two")], "already on: only the swap")
    }

    func testWithoutAutoEnableTheKeymapIsLoadedButLeftOff() {
        XCTAssertEqual(actions("com.game.one", enables: false), [.load("one")])
    }

    func testLeavingTheGameSwitchesOffWhatTheAppSwitchedOn() {
        XCTAssertEqual(actions("com.android.settings", loaded: "one", enabled: true, auto: true), [.disable])
    }

    func testAKeymapSwitchedOnByHandIsNeverTakenAway() {
        XCTAssertEqual(actions("com.android.settings", loaded: "one", enabled: true, auto: false), [])
    }

    func testNothingToDoWhenTheKeymapIsAlreadyOff() {
        XCTAssertEqual(actions("com.android.settings", loaded: "one", enabled: false, auto: true), [])
    }

    func testAnUnknownForegroundChangesNothing() {
        XCTAssertEqual(actions(nil, loaded: "one", enabled: true, auto: true), [], "a moment with no focus is not leaving the game")
    }

    func testIndexMapsEachGameToItsNewestKeymap() {
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        func profile(_ id: String, package: String?, at date: Date) -> Profile<Keymap> {
            Profile(id: id, name: id, payload: Keymap(package: package), modified: date)
        }
        let index = KeymapAutoSwitch.index(from: [
            profile("a-old", package: "com.game.a", at: old),
            profile("a-new", package: "com.game.a", at: new),
            profile("b", package: "com.game.b", at: old),
            profile("none", package: nil, at: new),
            profile("bad", package: "../etc", at: new),
        ])
        XCTAssertEqual(index, ["com.game.a": "a-new", "com.game.b": "b"])
        XCTAssertEqual(KeymapAutoSwitch.index(from: []), [:])
    }
}

final class SettingsCompatibilityTests: XCTestCase {
    func testSettingsSavedByAnOlderVersionStillLoadWithDefaultsForNewFields() throws {
        let old = #"{"quality":{"codec":"h265","maxSize":0,"bitRateMbps":50,"maxFPS":90,"keyFrameIntervalSeconds":1,"constantBitRate":true},"audioEnabled":false,"showTouches":true,"stayAwake":false,"turnScreenOffOnStart":false,"obsStreamEnabled":true,"obsStreamPort":9100}"#
        let settings = try JSONDecoder().decode(MirrorSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.quality.codec, .h265)
        XCTAssertEqual(settings.quality.bitRateMbps, 50)
        XCTAssertFalse(settings.audioEnabled)
        XCTAssertTrue(settings.showTouches)
        XCTAssertEqual(settings.obsStreamPort, 9100)
        XCTAssertTrue(settings.autoKeymap, "new fields take their defaults")
        XCTAssertTrue(settings.autoEnableKeymap)
    }

    func testEmptyAndUnknownSettingsGiveDefaults() throws {
        XCTAssertEqual(try JSONDecoder().decode(MirrorSettings.self, from: Data("{}".utf8)), MirrorSettings())
        XCTAssertEqual(try JSONDecoder().decode(MirrorSettings.self, from: Data(#"{"somethingNew":1}"#.utf8)), MirrorSettings())
    }

    func testTheNewSwitchesSurviveARoundTrip() throws {
        var settings = MirrorSettings()
        settings.autoKeymap = false
        settings.autoEnableKeymap = false
        XCTAssertEqual(try JSONDecoder().decode(MirrorSettings.self, from: try JSONEncoder().encode(settings)), settings)
    }

    func testProfileStoreLoadAllSkipsDamagedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProfileStore<Keymap>(kind: "keymap", root: root)
        try store.save(Profile(id: "a", name: "A", payload: Keymap(package: "com.game.a")))
        try store.save(Profile(id: "b", name: "B", payload: Keymap()))
        try Data("{ broken".utf8).write(to: root.appendingPathComponent("keymap/broken.json"))
        XCTAssertEqual(Set(store.loadAll().map(\.id)), ["a", "b"])
    }
}

@MainActor
final class AutoKeymapSessionTests: XCTestCase {
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var package: String?
        func set(_ value: String?) { lock.withLock { package = value } }
        func output() -> String {
            lock.withLock { package.map { "mFocusedApp=ActivityRecord{1 u0 \($0)/.Main t1}" } ?? "mCurrentFocus=null\nmFocusedApp=null" }
        }
    }

    private struct Rig {
        let session: DeviceSession
        let script: Script
        let loads: LoadLog
    }

    private final class LoadLog: @unchecked Sendable {
        var ids: [String] = []
    }

    private func makeRig(settings: MirrorSettings = MirrorSettings(), loadSucceeds: Bool = true) -> Rig {
        let adb = ADB(executable: URL(fileURLWithPath: "/usr/bin/false"))
        let session = DeviceSession(adb: adb, serial: "fake", settings: settings, cursorCapture: FakeCursorCapture())
        let loads = LoadLog()
        session.keymapIndex = { ["com.game.one": "one", "com.game.two": "two"] }
        session.loadKeymapProfile = { [weak session] id in
            guard loadSucceeds, let session else { return false }
            loads.ids.append(id)
            session.keymap.load(Keymap(), profile: ProfileSummary(id: id, name: "Keymap \(id)", modified: Date()))
            return true
        }
        let script = Script()
        session.foreground.start(interval: .milliseconds(15)) { script.output() }
        return Rig(session: session, script: script, loads: loads)
    }

    private func waitUntil(_ description: String, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "timed out: \(description)")
    }

    func testOpeningAGameLoadsAndEnablesItsKeymapAndLeavingSwitchesItOff() async {
        let rig = makeRig()
        defer { rig.session.stop() }

        rig.script.set("com.game.one")
        await waitUntil("keymap on") { rig.session.keymap.isEnabled }
        XCTAssertEqual(rig.session.keymap.profile?.id, "one")

        rig.script.set("com.android.settings")
        await waitUntil("keymap off") { !rig.session.keymap.isEnabled }
        XCTAssertEqual(rig.session.keymap.profile?.id, "one", "it stays loaded, only switched off")

        rig.script.set("com.game.one")
        await waitUntil("on again") { rig.session.keymap.isEnabled }
        XCTAssertEqual(rig.loads.ids, ["one"], "no need to load it twice")
    }

    func testSwitchingBetweenTwoGamesSwapsTheKeymap() async {
        let rig = makeRig()
        defer { rig.session.stop() }
        rig.script.set("com.game.one")
        await waitUntil("one on") { rig.session.keymap.profile?.id == "one" && rig.session.keymap.isEnabled }
        rig.script.set("com.game.two")
        await waitUntil("two loaded") { rig.session.keymap.profile?.id == "two" }
        XCTAssertTrue(rig.session.keymap.isEnabled)
    }

    func testAKeymapSwitchedOnByHandSurvivesLeavingAGame() async {
        let rig = makeRig()
        defer { rig.session.stop() }
        rig.session.keymap.load(Keymap(), profile: ProfileSummary(id: "mine", name: "Mine", modified: Date()))
        rig.session.keymap.isEnabled = true

        rig.script.set("com.android.settings")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(rig.session.keymap.isEnabled)
        XCTAssertEqual(rig.session.keymap.profile?.id, "mine")
    }

    func testWithoutAutoEnableTheKeymapLoadsButStaysOff() async {
        var settings = MirrorSettings()
        settings.autoEnableKeymap = false
        let rig = makeRig(settings: settings)
        defer { rig.session.stop() }
        rig.script.set("com.game.one")
        await waitUntil("loaded") { rig.session.keymap.profile?.id == "one" }
        XCTAssertFalse(rig.session.keymap.isEnabled)
    }

    func testTurningTheFeatureOffDoesNothing() async {
        var settings = MirrorSettings()
        settings.autoKeymap = false
        let rig = makeRig(settings: settings)
        defer { rig.session.stop() }
        rig.script.set("com.game.one")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(rig.session.keymap.profile)
        XCTAssertTrue(rig.loads.ids.isEmpty)
    }

    func testNothingHappensWhileTheEditorIsOpen() async {
        let rig = makeRig()
        defer { rig.session.stop() }
        rig.session.keymap.isEditing = true
        rig.script.set("com.game.one")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(rig.session.keymap.profile)
        XCTAssertFalse(rig.session.keymap.isEnabled)
    }

    func testAKeymapThatFailsToLoadIsNotSwitchedOn() async {
        let rig = makeRig(loadSucceeds: false)
        defer { rig.session.stop() }
        rig.script.set("com.game.one")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(rig.session.keymap.isEnabled)
    }

    func testAMomentWithNoFocusDoesNotSwitchTheKeymapOff() async {
        let rig = makeRig()
        defer { rig.session.stop() }
        rig.script.set("com.game.one")
        await waitUntil("on") { rig.session.keymap.isEnabled }
        rig.script.set(nil)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(rig.session.keymap.isEnabled)
    }
}
