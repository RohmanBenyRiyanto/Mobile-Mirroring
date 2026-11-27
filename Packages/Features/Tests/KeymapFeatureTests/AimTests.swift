import XCTest
import FeatureTestSupport
@testable import DomainModels
@testable import KeymapFeature

private let keyTilde: UInt16 = 50, keyW: UInt16 = 13

private func aim(x: Double = 0.7, y: Double = 0.5, sensitivity: Double = 2, radius: Double = 0.1) -> KeymapElement {
    KeymapElement(label: "Look", position: NormalizedPoint(x: x, y: y), action: .aim(toggleKey: keyTilde, sensitivity: sensitivity, radius: radius))
}

private func mouse(_ button: Int, _ mode: ButtonMode, x: Double = 0.9, y: Double = 0.8) -> KeymapElement {
    KeymapElement(label: "Fire", position: NormalizedPoint(x: x, y: y), action: .mouseButton(button: button, mode: mode))
}

private struct Seen {
    let action: TouchAction
    let x: Double
    let y: Double
    let slot: PointerID
}

private func touches(_ actions: [KeymapEngine.Action]) -> [Seen] {
    actions.compactMap { action in
        guard case let .send(.touch(kind, position, _, pointer)) = action else { return nil }
        return Seen(action: kind, x: Double(position.x), y: Double(position.y), slot: pointer)
    }
}

final class AimEngineTests: XCTestCase {
    private let phone = CGSize(width: 1080, height: 2340)
    /// Centre of the look area (0.7, 0.5) in frame pixels, and its reach (a tenth of the shorter edge).
    private let centreX = 0.7 * 1079, centreY = 0.5 * 2339, reach = 108.0

    private func engine(_ elements: [KeymapElement]) -> KeymapEngine { KeymapEngine(keymap: Keymap(elements: elements)) }

    func testTheToggleKeyTurnsFreeLookOnAndOffWithoutTouchingTheScreen() {
        var engine = engine([aim()])
        XCTAssertFalse(engine.isAiming)
        XCTAssertEqual(engine.keyDown(keyTilde, frameSize: phone), [])
        XCTAssertTrue(engine.isAiming)
        _ = engine.keyUp(keyTilde, frameSize: phone)
        XCTAssertEqual(engine.keyDown(keyTilde, frameSize: phone), [], "no finger was down, so nothing to lift")
        XCTAssertFalse(engine.isAiming)
    }

    func testMouseMovementIsIgnoredUntilAimingStarts() {
        var engine = engine([aim()])
        XCTAssertEqual(engine.mouseMoved(deltaX: 10, deltaY: 10, frameSize: phone), [])
    }

    func testFirstMovementPutsAFingerAtTheCentreThenDragsIt() throws {
        var engine = engine([aim(sensitivity: 2)])
        _ = engine.keyDown(keyTilde, frameSize: phone)

        let seen = touches(engine.mouseMoved(deltaX: 10, deltaY: 5, frameSize: phone))
        XCTAssertEqual(seen.map(\.action), [.down, .move])
        XCTAssertEqual(seen[0].x, centreX, accuracy: 0.6)
        XCTAssertEqual(seen[0].y, centreY, accuracy: 0.6)
        // sensitivity 2 on a 1080-wide screen: 2 px per mouse point; positive y is down
        XCTAssertEqual(seen[1].x, centreX + 20, accuracy: 1.1)
        XCTAssertEqual(seen[1].y, centreY + 10, accuracy: 1.1)

        let next = touches(engine.mouseMoved(deltaX: -5, deltaY: 0, frameSize: phone))
        XCTAssertEqual(next.map(\.action), [.move], "the same finger keeps moving")
        XCTAssertEqual(next[0].x, centreX + 10, accuracy: 1.1)
    }

    func testSensitivityScalesWithTheShorterEdgeSoLandscapeFeelsTheSame() throws {
        var portrait = engine([aim(sensitivity: 2)])
        var landscape = engine([aim(sensitivity: 2)])
        _ = portrait.keyDown(keyTilde, frameSize: phone)
        _ = landscape.keyDown(keyTilde, frameSize: CGSize(width: 2340, height: 1080))
        let a = try XCTUnwrap(touches(portrait.mouseMoved(deltaX: 10, deltaY: 0, frameSize: phone)).last)
        let b = try XCTUnwrap(touches(landscape.mouseMoved(deltaX: 10, deltaY: 0, frameSize: CGSize(width: 2340, height: 1080))).last)
        XCTAssertEqual(a.x - centreX, 20, accuracy: 1.1)
        XCTAssertEqual(b.x - 0.7 * 2339, 20, accuracy: 1.1)

        var fine = engine([aim(sensitivity: 1)])
        _ = fine.keyDown(keyTilde, frameSize: CGSize(width: 2160, height: 4680))
        let big = try XCTUnwrap(touches(fine.mouseMoved(deltaX: 10, deltaY: 0, frameSize: CGSize(width: 2160, height: 4680))).last)
        XCTAssertEqual(big.x - 0.7 * 2159, 20, accuracy: 1.5, "a screen twice as dense moves twice the pixels for the same hand motion")
    }

    func testGoingPastTheEdgePutsTheFingerBackInTheMiddle() throws {
        var engine = engine([aim(sensitivity: 2, radius: 0.1)]) // reach 108 px = 54 mouse points
        _ = engine.keyDown(keyTilde, frameSize: phone)
        _ = engine.mouseMoved(deltaX: 40, deltaY: 0, frameSize: phone)

        let wrap = touches(engine.mouseMoved(deltaX: 20, deltaY: 0, frameSize: phone)) // 60 points = 120 px > 108
        XCTAssertEqual(wrap.map(\.action), [.up, .down], "lift and touch down again at the centre")
        XCTAssertEqual(wrap[1].x, centreX, accuracy: 0.6)
        XCTAssertEqual(wrap[0].slot, wrap[1].slot, "the same finger")

        let after = touches(engine.mouseMoved(deltaX: 5, deltaY: 0, frameSize: phone))
        XCTAssertEqual(after.first?.action, .move)
        XCTAssertEqual(after[0].x, centreX + 10, accuracy: 1.1, "continues from the centre")
    }

    func testSwitchingFreeLookOffLiftsTheFinger() {
        var engine = engine([aim()])
        _ = engine.keyDown(keyTilde, frameSize: phone)
        _ = engine.mouseMoved(deltaX: 5, deltaY: 5, frameSize: phone)
        _ = engine.keyUp(keyTilde, frameSize: phone)
        XCTAssertEqual(touches(engine.keyDown(keyTilde, frameSize: phone)).map(\.action), [.up])
        XCTAssertFalse(engine.isAiming)
        XCTAssertEqual(engine.mouseMoved(deltaX: 5, deltaY: 5, frameSize: phone), [])
    }

    func testMouseButtonsOnlyWorkWhileAiming() throws {
        var engine = engine([aim(), mouse(0, .hold)])
        XCTAssertTrue(engine.handlesMouseButton(0))
        XCTAssertFalse(engine.handlesMouseButton(1))
        XCTAssertEqual(engine.mouseDown(button: 0, frameSize: phone), [], "not aiming: the click is a normal click")

        _ = engine.keyDown(keyTilde, frameSize: phone)
        let down = touches(engine.mouseDown(button: 0, frameSize: phone))
        XCTAssertEqual(down.map(\.action), [.down])
        XCTAssertEqual(down[0].x, 0.9 * 1079, accuracy: 0.6)
        XCTAssertEqual(touches(engine.mouseUp(button: 0, frameSize: phone)).map(\.action), [.up])
    }

    func testAMouseButtonHeldWhenFreeLookEndsIsLifted() {
        var engine = engine([aim(), mouse(0, .hold)])
        _ = engine.keyDown(keyTilde, frameSize: phone)
        _ = engine.mouseDown(button: 0, frameSize: phone)
        _ = engine.keyUp(keyTilde, frameSize: phone)
        XCTAssertEqual(touches(engine.keyDown(keyTilde, frameSize: phone)).map(\.action), [.up])
    }

    func testLookAndFireUseDifferentFingers() throws {
        var engine = engine([aim(), mouse(0, .hold)])
        _ = engine.keyDown(keyTilde, frameSize: phone)
        let look = try XCTUnwrap(touches(engine.mouseMoved(deltaX: 3, deltaY: 0, frameSize: phone)).first)
        let fire = try XCTUnwrap(touches(engine.mouseDown(button: 0, frameSize: phone)).first)
        XCTAssertNotEqual(look.slot, fire.slot)
    }

    func testReleaseAllEndsFreeLookAndLiftsEverything() {
        var engine = engine([aim(), mouse(0, .hold)])
        _ = engine.keyDown(keyTilde, frameSize: phone)
        _ = engine.mouseMoved(deltaX: 3, deltaY: 0, frameSize: phone)
        _ = engine.mouseDown(button: 0, frameSize: phone)

        let lifted = touches(engine.releaseAll(frameSize: phone))
        XCTAssertEqual(lifted.map(\.action), [.up, .up])
        XCTAssertFalse(engine.isAiming)
        XCTAssertEqual(engine.releaseAll(frameSize: phone), [])
    }

    func testAKeymapWithoutAFreeLookAreaIgnoresTheToggleKey() {
        var engine = engine([mouse(0, .hold)])
        XCTAssertFalse(engine.handles(keyTilde))
        XCTAssertEqual(engine.keyDown(keyTilde, frameSize: phone), [])
        XCTAssertFalse(engine.isAiming)
    }

    func testAimWorksAlongsideAJoystick() throws {
        let stick = KeymapElement(position: NormalizedPoint(x: 0.2, y: 0.7),
                                  action: .joystick(up: keyW, left: 0, down: 1, right: 2, radius: 0.1, response: 0))
        var engine = engine([aim(), stick])
        _ = engine.keyDown(keyTilde, frameSize: phone)
        let walking = try XCTUnwrap(touches(engine.keyDown(keyW, frameSize: phone)).first)
        let looking = try XCTUnwrap(touches(engine.mouseMoved(deltaX: 4, deltaY: 0, frameSize: phone)).first)
        XCTAssertNotEqual(walking.slot, looking.slot)
    }
}

final class AimModelTests: XCTestCase {
    func testValidationClampsSensitivityAndRadius() throws {
        let checked = try Keymap(elements: [aim(sensitivity: 500, radius: 9)]).validated()
        guard case let .aim(_, sensitivity, radius) = checked.elements[0].action else { return XCTFail() }
        XCTAssertEqual(sensitivity, KeymapAction.sensitivityRange.upperBound)
        XCTAssertEqual(radius, KeymapAction.radiusRange.upperBound)
    }

    func testValidationRejectsBadAimSettings() {
        XCTAssertThrowsError(try Keymap(elements: [aim(sensitivity: .nan)]).validated()) { XCTAssertEqual($0 as? Keymap.Problem, .invalidAim) }
        XCTAssertThrowsError(try Keymap(elements: [aim(), aim()]).validated(), "only one look area") { XCTAssertEqual($0 as? Keymap.Problem, .invalidAim) }
        XCTAssertThrowsError(try Keymap(elements: [mouse(9, .tap)]).validated()) { XCTAssertEqual($0 as? Keymap.Problem, .invalidAim) }
        XCTAssertThrowsError(try Keymap(elements: [mouse(-1, .tap)]).validated())
        XCTAssertNoThrow(try Keymap(elements: [aim(), mouse(0, .hold), mouse(1, .tap)]).validated())
    }

    func testAimAndMouseButtonsSurviveJSON() throws {
        let keymap = Keymap(elements: [aim(), mouse(0, .hold)])
        let data = try JSONEncoder().encode(keymap)
        XCTAssertEqual(try JSONDecoder().decode(Keymap.self, from: data), keymap)
    }
}

@MainActor
final class AimControllerTests: XCTestCase {
    private final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [TouchAction] = []
        func add(_ message: ControlMessage) { if case let .touch(action, _, _, _) = message { lock.withLock { items.append(action) } } }
        var actions: [TouchAction] { lock.withLock { items } }
    }

    private func makeController(_ elements: [KeymapElement]) -> (KeymapController, Sent, FakeCursorCapture) {
        let sent = Sent()
        let cursor = FakeCursorCapture()
        let controller = KeymapController(send: { sent.add($0) }, cursor: cursor)
        controller.updateFrameSize(CGSize(width: 1080, height: 2340))
        controller.load(Keymap(elements: elements), profile: nil)
        controller.isEnabled = true
        return (controller, sent, cursor)
    }

    func testFreeLookCapturesThePointerAndReleasingFreesIt() {
        let (controller, _, cursor) = makeController([aim()])
        XCTAssertFalse(cursor.isCaptured)
        XCTAssertTrue(controller.keyDown(keyTilde))
        XCTAssertTrue(controller.isAiming)
        XCTAssertTrue(cursor.isCaptured)
        _ = controller.keyUp(keyTilde)
        _ = controller.keyDown(keyTilde)
        XCTAssertFalse(controller.isAiming)
        XCTAssertEqual(cursor.history, [true, false])
    }

    func testMouseEventsAreConsumedOnlyWhileAiming() {
        let (controller, sent, _) = makeController([aim(), mouse(0, .hold)])
        XCTAssertFalse(controller.mouseMoved(deltaX: 5, deltaY: 5))
        XCTAssertFalse(controller.mouseDown(button: 0))
        _ = controller.keyDown(keyTilde)
        XCTAssertTrue(controller.mouseMoved(deltaX: 5, deltaY: 5))
        XCTAssertTrue(controller.mouseDown(button: 0))
        XCTAssertTrue(controller.mouseDown(button: 1), "an unmapped click is swallowed, never tapped on the phone by accident")
        XCTAssertTrue(controller.mouseUp(button: 0))
        XCTAssertEqual(sent.actions.filter { $0 == .up }.count, 1)
    }

    func testTurningTheKeymapOffFreesThePointerAndLiftsFingers() {
        let (controller, sent, cursor) = makeController([aim(), mouse(0, .hold)])
        _ = controller.keyDown(keyTilde)
        _ = controller.mouseMoved(deltaX: 4, deltaY: 0)
        _ = controller.mouseDown(button: 0)
        controller.isEnabled = false
        XCTAssertFalse(cursor.isCaptured, "the pointer must never stay locked")
        XCTAssertFalse(controller.isAiming)
        XCTAssertEqual(sent.actions.filter { $0 == .down }.count, sent.actions.filter { $0 == .up }.count)
    }

    func testLoosingFocusAndRotationFreeThePointer() {
        let (controller, _, cursor) = makeController([aim()])
        _ = controller.keyDown(keyTilde)
        controller.releaseAll() // what the view does when the window stops being key
        XCTAssertFalse(cursor.isCaptured)

        _ = controller.keyUp(keyTilde)
        _ = controller.keyDown(keyTilde)
        controller.updateFrameSize(CGSize(width: 2340, height: 1080))
        XCTAssertFalse(cursor.isCaptured)
    }

    func testUnloadingFreesThePointer() {
        let (controller, _, cursor) = makeController([aim()])
        _ = controller.keyDown(keyTilde)
        controller.unload()
        XCTAssertFalse(cursor.isCaptured)
    }
}
