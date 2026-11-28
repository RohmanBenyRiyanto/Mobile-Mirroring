import XCTest
import FeatureTestSupport
import TestSupport
@testable import DomainModels
@testable import KeymapFeature
@testable import Persistence

private let key = (a: UInt16(0), s: UInt16(1), d: UInt16(2), q: UInt16(12), w: UInt16(13), space: UInt16(49))

private func button(_ keyCode: UInt16, _ mode: ButtonMode, x: Double = 0.5, y: Double = 0.5, label: String = "") -> KeymapElement {
    KeymapElement(label: label, position: NormalizedPoint(x: x, y: y), action: .button(key: keyCode, mode: mode))
}

private func touch(_ message: ControlMessage) -> (action: TouchAction, position: TouchPosition, pointer: PointerID)? {
    if case let .touch(action, position, _, pointer) = message { return (action, position, pointer) }
    return nil
}

final class KeymapModelTests: XCTestCase {
    func testKeymapSurvivesTheProfileStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProfileStore<Keymap>(kind: "keymap", root: root)
        let keymap = Keymap(package: "com.tencent.ig", elements: [button(key.q, .tap, x: 0.8, y: 0.7, label: "Reload"), button(key.space, .hold)])

        try store.save(Profile(id: "com.tencent.ig", name: "PUBG", payload: keymap))
        XCTAssertEqual(try store.load(id: "com.tencent.ig").payload, keymap)
    }

    func testValidationClampsPositionsAndCleansLabels() throws {
        let keymap = Keymap(elements: [button(key.q, .tap, x: -2, y: 7, label: "  Bad\u{1B}[0m  ")])
        let checked = try keymap.validated()
        XCTAssertEqual(checked.elements[0].position, NormalizedPoint(x: 0, y: 1))
        XCTAssertEqual(checked.elements[0].label, "Bad[0m")
    }

    func testValidationRejectsNonsense() {
        XCTAssertThrowsError(try Keymap(elements: [button(key.q, .tap, x: .nan)]).validated()) {
            XCTAssertEqual($0 as? Keymap.Problem, .invalidPosition(label: ""))
        }
        XCTAssertThrowsError(try Keymap(elements: Array(repeating: button(key.q, .tap), count: Keymap.maxElements + 1)).validated()) {
            XCTAssertEqual($0 as? Keymap.Problem, .tooManyElements)
        }
        XCTAssertThrowsError(try Keymap(package: "../etc", elements: []).validated()) {
            XCTAssertEqual($0 as? Keymap.Problem, .invalidPackage("../etc"))
        }
        XCTAssertNoThrow(try Keymap(package: "com.tencent.ig").validated())
        XCTAssertNoThrow(try Keymap(package: nil).validated())
    }

    func testTheExampleKeymapInTheDocsStillImports() throws {
        let file = projectFile("Resources/Examples/example.benzkeymap")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let imported = try ProfileStore<Keymap>(kind: "keymap", root: root).importData(try Data(contentsOf: file))
        let keymap = try imported.payload.validated()
        XCTAssertEqual(imported.name, "Example keymap")
        XCTAssertEqual(keymap.elements.map(\.label), ["Move", "Look", "Fire (mouse)", "Skill 1", "Skill 3 (aimed)", "Skill 2", "Fire", "Scope"])
        XCTAssertEqual(keymap.elements.map(\.keys), [[13, 0, 1, 2], [50], [], [12], [15], [14], [49], [48]])
    }

    func testKeyNames() {
        XCTAssertEqual(KeyNames.name(for: 13), "W")
        XCTAssertEqual(KeyNames.name(for: 49), "Space")
        XCTAssertEqual(KeyNames.name(for: 126), "↑")
        XCTAssertEqual(KeyNames.name(for: 250), "Key 250")
        XCTAssertEqual(KeyNames.modifier(for: 56), .shift)
        XCTAssertEqual(KeyNames.modifier(for: 62), .control)
        XCTAssertNil(KeyNames.modifier(for: 13))
    }

    func testPointerSlotsAreDistinctSmallIdsOnTheWire() {
        for slot in 0..<PointerID.slotCount {
            let message = ControlMessage.touch(.down, TouchPosition(x: 1, y: 1, frameWidth: 10, frameHeight: 10), pressure: 1, pointer: .slot(slot))
            XCTAssertEqual(message.serialized.readBigEndian(UInt64.self, at: 2), UInt64(slot))
        }
        XCTAssertNotEqual(PointerID.slot(0), .mouse)
    }
}

final class KeymapEngineTests: XCTestCase {
    private let phone = CGSize(width: 1080, height: 2340)

    func testTapPutsAFingerDownThenLiftsItShortlyAfter() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.q, .tap, x: 0.25, y: 0.5)]))
        let actions = engine.keyDown(key.q, frameSize: phone)
        XCTAssertEqual(actions.count, 2)

        guard case let .send(down) = actions[0], case let .sendAfter(delay, up, slot) = actions[1] else { return XCTFail("\(actions)") }
        let pressed = try XCTUnwrap(touch(down)), lifted = try XCTUnwrap(touch(up))
        XCTAssertEqual(pressed.action, .down)
        XCTAssertEqual(lifted.action, .up)
        XCTAssertEqual(pressed.position, lifted.position)
        XCTAssertEqual(pressed.pointer, .slot(0))
        XCTAssertEqual(slot, 0)
        XCTAssertEqual(delay, KeymapEngine.tapDuration)
        XCTAssertEqual(Double(pressed.position.x), 0.25 * 1079, accuracy: 0.51)
        XCTAssertEqual(Double(pressed.position.y), 0.5 * 2339, accuracy: 0.51)
        XCTAssertEqual(pressed.position.frameWidth, 1080)
    }

    func testReleasingATapKeyDoesNothing() {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.q, .tap)]))
        _ = engine.keyDown(key.q, frameSize: phone)
        XCTAssertEqual(engine.keyUp(key.q, frameSize: phone), [])
    }

    func testAQuickSecondTapUsesAnotherSlotUntilTheFirstIsFinished() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.q, .tap)]))
        func slotUsed(_ actions: [KeymapEngine.Action]) throws -> Int {
            guard case let .send(message) = actions[0] else { throw XCTSkip("unexpected") }
            return try XCTUnwrap(touch(message)).pointer == .slot(0) ? 0 : 1
        }
        let first = engine.keyDown(key.q, frameSize: phone)
        _ = engine.keyUp(key.q, frameSize: phone)
        let second = engine.keyDown(key.q, frameSize: phone)
        _ = engine.keyUp(key.q, frameSize: phone)
        XCTAssertEqual(try slotUsed(first), 0)
        XCTAssertEqual(try slotUsed(second), 1, "slot 0 still has its lift pending")

        engine.finishTap(slot: 0)
        let third = engine.keyDown(key.q, frameSize: phone)
        XCTAssertEqual(try slotUsed(third), 0, "slot 0 is free again")
    }

    func testHoldKeepsTheFingerDownUntilTheKeyIsReleased() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.space, .hold)]))
        let down = engine.keyDown(key.space, frameSize: phone)
        XCTAssertEqual(down.count, 1)
        XCTAssertEqual(try XCTUnwrap(touch(try XCTUnwrap(down.first?.message))).action, .down)

        XCTAssertEqual(engine.keyDown(key.space, frameSize: phone), [], "auto-repeat while held does nothing")
        let up = engine.keyUp(key.space, frameSize: phone)
        XCTAssertEqual(try XCTUnwrap(touch(try XCTUnwrap(up.first?.message))).action, .up)
        XCTAssertEqual(engine.keyUp(key.space, frameSize: phone), [])
    }

    func testToggleAlternatesBetweenDownAndUp() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.q, .toggle)]))
        var seen: [TouchAction] = []
        for _ in 0..<4 {
            let actions = engine.keyDown(key.q, frameSize: phone)
            seen.append(try XCTUnwrap(touch(try XCTUnwrap(actions.first?.message))).action)
            XCTAssertEqual(engine.keyUp(key.q, frameSize: phone), [], "letting go of a toggle key does nothing")
        }
        XCTAssertEqual(seen, [.down, .up, .down, .up])
    }

    func testHeldKeysUseDifferentFingers() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.w, .hold, x: 0.2), button(key.space, .hold, x: 0.8)]))
        let first = try XCTUnwrap(touch(try XCTUnwrap(engine.keyDown(key.w, frameSize: phone).first?.message)))
        let second = try XCTUnwrap(touch(try XCTUnwrap(engine.keyDown(key.space, frameSize: phone).first?.message)))
        XCTAssertNotEqual(first.pointer, second.pointer)

        _ = engine.keyUp(key.w, frameSize: phone)
        let reused = try XCTUnwrap(touch(try XCTUnwrap(engine.keyDown(key.w, frameSize: phone).first?.message)))
        XCTAssertEqual(reused.pointer, first.pointer, "the freed finger is reused")
    }

    func testOneKeyCanDriveSeveralButtons() {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.q, .hold, x: 0.1), button(key.q, .hold, x: 0.9)]))
        XCTAssertEqual(engine.keyDown(key.q, frameSize: phone).count, 2)
        XCTAssertEqual(engine.keyUp(key.q, frameSize: phone).count, 2)
    }

    func testReleaseAllLiftsEveryFingerAndTheEngineKeepsWorking() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.w, .hold), button(key.q, .toggle), button(key.space, .hold)]))
        _ = engine.keyDown(key.w, frameSize: phone)
        _ = engine.keyDown(key.q, frameSize: phone)

        let lifted = engine.releaseAll(frameSize: phone)
        XCTAssertEqual(lifted.count, 2)
        XCTAssertTrue(lifted.allSatisfy { touch($0.message!)?.action == .up })
        XCTAssertEqual(engine.releaseAll(frameSize: phone), [], "nothing left to lift")

        XCTAssertEqual(engine.keyDown(key.w, frameSize: phone).count, 1, "a key pressed before the reset can be pressed again")
        XCTAssertEqual(try XCTUnwrap(touch(try XCTUnwrap(engine.keyDown(key.space, frameSize: phone).first?.message))).pointer, .slot(1))
    }

    func testRunningOutOfFingersIgnoresTheExtraButton() {
        let elements = (0..<11).map { button(UInt16($0), .hold) }
        var engine = KeymapEngine(keymap: Keymap(elements: elements))
        let results = (0..<11).map { engine.keyDown(UInt16($0), frameSize: phone).count }
        XCTAssertEqual(results.prefix(10).reduce(0, +), 10)
        XCTAssertEqual(results[10], 0, "the server tracks at most 10 pointers")
    }

    func testTheSameRatioLandsInTheSameSpotOnADifferentScreen() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.q, .hold, x: 0.75, y: 0.25)]))
        let small = try XCTUnwrap(touch(try XCTUnwrap(engine.keyDown(key.q, frameSize: CGSize(width: 720, height: 1280)).first?.message)))
        _ = engine.keyUp(key.q, frameSize: CGSize(width: 720, height: 1280))
        let large = try XCTUnwrap(touch(try XCTUnwrap(engine.keyDown(key.q, frameSize: CGSize(width: 2560, height: 1600)).first?.message)))
        XCTAssertEqual(Double(small.position.x) / 719, 0.75, accuracy: 0.002)
        XCTAssertEqual(Double(large.position.x) / 2559, 0.75, accuracy: 0.002)
        XCTAssertEqual(Double(large.position.y) / 1599, 0.25, accuracy: 0.002)
    }

    func testUnboundKeysAreNotHandled() {
        var engine = KeymapEngine(keymap: Keymap(elements: [button(key.q, .tap)]))
        XCTAssertTrue(engine.handles(key.q))
        XCTAssertFalse(engine.handles(key.a))
        XCTAssertEqual(engine.keyDown(key.a, frameSize: phone), [])
    }
}

private extension KeymapEngine.Action {
    var message: ControlMessage? {
        switch self {
        case let .send(message): return message
        case let .sendAfter(_, message, _): return message
        }
    }
}

@MainActor
final class KeymapControllerTests: XCTestCase {
    private final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [ControlMessage] = []
        func add(_ message: ControlMessage) { lock.withLock { items.append(message) } }
        var all: [ControlMessage] { lock.withLock { items } }
        var actions: [TouchAction] { all.compactMap { touch($0)?.action } }
    }

    private func makeController(_ elements: [KeymapElement]) -> (KeymapController, Sent) {
        let sent = Sent()
        let controller = KeymapController(send: { sent.add($0) }, cursor: FakeCursorCapture())
        controller.updateFrameSize(CGSize(width: 1080, height: 2340))
        controller.load(Keymap(elements: elements), profile: ProfileSummary(id: "test", name: "Test", modified: Date()))
        return (controller, sent)
    }

    func testDoesNothingUntilEnabled() {
        let (controller, sent) = makeController([button(key.q, .hold)])
        XCTAssertFalse(controller.handles(key.q))
        XCTAssertFalse(controller.keyDown(key.q))
        XCTAssertTrue(sent.all.isEmpty)
        controller.isEnabled = true
        XCTAssertTrue(controller.keyDown(key.q))
        XCTAssertFalse(controller.keyDown(key.a), "unbound keys are left for normal typing")
    }

    func testTapLiftsTheFingerAfterTheDelay() async throws {
        let (controller, sent) = makeController([button(key.q, .tap)])
        controller.isEnabled = true
        XCTAssertTrue(controller.keyDown(key.q))
        XCTAssertEqual(sent.actions, [.down])
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(sent.actions, [.down, .up])
    }

    func testSwitchingOffLiftsHeldFingers() {
        let (controller, sent) = makeController([button(key.q, .hold)])
        controller.isEnabled = true
        _ = controller.keyDown(key.q)
        controller.isEnabled = false
        XCTAssertEqual(sent.actions, [.down, .up])
    }

    func testRotationLiftsHeldFingersBeforeTheFrameChanges() {
        let (controller, sent) = makeController([button(key.q, .hold)])
        controller.isEnabled = true
        _ = controller.keyDown(key.q)
        controller.updateFrameSize(CGSize(width: 2340, height: 1080))
        XCTAssertEqual(sent.actions, [.down, .up])
        controller.updateFrameSize(CGSize(width: 2340, height: 1080))
        XCTAssertEqual(sent.actions.count, 2, "an unchanged size is not a rotation")
    }

    func testLoadingAnotherKeymapLiftsFingersAndStillDeliversPendingLifts() async throws {
        let (controller, sent) = makeController([button(key.q, .tap), button(key.w, .hold)])
        controller.isEnabled = true
        _ = controller.keyDown(key.q)
        _ = controller.keyDown(key.w)
        controller.load(Keymap(elements: [button(key.s, .hold)]), profile: nil)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(sent.actions.filter { $0 == .down }.count, 2)
        XCTAssertEqual(sent.actions.filter { $0 == .up }.count, 2, "every finger that went down came up")
        XCTAssertFalse(controller.handles(key.q))
        XCTAssertTrue(controller.handles(key.s))
    }

    func testUnloadingSwitchesTheKeymapOff() {
        let (controller, _) = makeController([button(key.q, .hold)])
        controller.isEnabled = true
        controller.unload()
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.hasKeymap)
        XCTAssertNil(controller.profile)
    }
}
