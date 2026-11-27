import XCTest
import FeatureTestSupport
@testable import DomainModels
@testable import KeymapFeature

private let keyQ: UInt16 = 12, keyE: UInt16 = 14

private func skill(_ key: UInt16 = keyQ, cast: SkillCast = .onRelease, x: Double = 0.8, y: Double = 0.8,
                   radius: Double = 0.1, range: Double = 0.2, hero: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5)) -> KeymapElement {
    KeymapElement(label: "Skill", position: NormalizedPoint(x: x, y: y),
                  action: .skillShot(key: key, cast: cast, radius: radius, range: range, hero: hero))
}

private struct Seen {
    let action: TouchAction
    let x: Double
    let y: Double
    let slot: PointerID
}

private func touches(_ actions: [KeymapEngine.Action]) -> [Seen] {
    actions.compactMap { action in
        let message: ControlMessage
        switch action {
        case let .send(sent): message = sent
        case let .sendAfter(_, sent, _): message = sent
        }
        guard case let .touch(kind, position, _, pointer) = message else { return nil }
        return Seen(action: kind, x: Double(position.x), y: Double(position.y), slot: pointer)
    }
}

final class SkillShotEngineTests: XCTestCase {
    private let phone = CGSize(width: 1080, height: 2340)
    /// The skill button (0.8, 0.8) in frame pixels, and a full drag (radius 0.1 of the shorter edge).
    private let buttonX = 0.8 * 1079, buttonY = 0.8 * 2339, fullReach = 108.0

    private func engine(_ elements: [KeymapElement]) -> KeymapEngine { KeymapEngine(keymap: Keymap(elements: elements)) }

    func testHoldingTheKeyPutsAFingerOnTheButtonAndReleasingCasts() throws {
        var engine = engine([skill()])
        _ = engine.pointerMoved(to: CGPoint(x: 0.5, y: 0.5), frameSize: phone) // on the hero: no direction yet

        let down = touches(engine.keyDown(keyQ, frameSize: phone))
        XCTAssertEqual(down.map(\.action), [.down])
        XCTAssertEqual(down[0].x, buttonX, accuracy: 0.6)
        XCTAssertEqual(down[0].y, buttonY, accuracy: 0.6)

        let cast = touches(engine.keyUp(keyQ, frameSize: phone))
        XCTAssertEqual(cast.map(\.action), [.up])
        XCTAssertEqual(cast[0].slot, down[0].slot)
    }

    func testTheFingerFollowsTheMouseWhileTheKeyIsHeld() throws {
        var engine = engine([skill(range: 0.2)]) // full range = 0.2 of the 1080 px shorter edge = 216 px
        _ = engine.keyDown(keyQ, frameSize: phone)

        // 108 px (0.1 of the width) to the right of the hero: half range -> half reach
        let right = try XCTUnwrap(touches(engine.pointerMoved(to: CGPoint(x: 0.6, y: 0.5), frameSize: phone)).first)
        XCTAssertEqual(right.action, .move)
        XCTAssertEqual(right.x - buttonX, fullReach / 2, accuracy: 1.1)
        XCTAssertEqual(right.y, buttonY, accuracy: 1.1)

        // far beyond the range: full reach, never more
        let far = try XCTUnwrap(touches(engine.pointerMoved(to: CGPoint(x: 1.0, y: 0.5), frameSize: phone)).first)
        XCTAssertEqual(far.x - buttonX, fullReach, accuracy: 1.1)

        // above the hero: the finger goes up (screen y grows downwards)
        let up = try XCTUnwrap(touches(engine.pointerMoved(to: CGPoint(x: 0.5, y: 0.0), frameSize: phone)).first)
        XCTAssertEqual(up.x, buttonX, accuracy: 1.1)
        XCTAssertEqual(up.y - buttonY, -fullReach, accuracy: 1.1)

        let left = try XCTUnwrap(touches(engine.pointerMoved(to: CGPoint(x: 0.0, y: 0.5), frameSize: phone)).first)
        XCTAssertEqual(left.x - buttonX, -fullReach, accuracy: 1.1)
    }

    func testDirectionIsMeasuredInPixelsNotInRatios() throws {
        var engine = engine([skill(range: 0.5)]) // range 540 px
        _ = engine.keyDown(keyQ, frameSize: phone)
        // equal ratio offsets are very different pixel offsets on a tall screen: (0.1, 0.1) -> (108, 234) px
        let diagonal = try XCTUnwrap(touches(engine.pointerMoved(to: CGPoint(x: 0.6, y: 0.6), frameSize: phone)).first)
        let dx = diagonal.x - buttonX, dy = diagonal.y - buttonY
        XCTAssertEqual(atan2(dy, dx), atan2(234.0, 108.0), accuracy: 0.03, "the angle follows the real pixel offset")
        XCTAssertEqual((dx * dx + dy * dy).squareRoot(), fullReach * (257.7 / 540), accuracy: 2)
    }

    func testTheHeroPositionIsTheOriginOfTheDirection() throws {
        var engine = engine([skill(hero: NormalizedPoint(x: 0.2, y: 0.5))])
        _ = engine.keyDown(keyQ, frameSize: phone)
        let move = try XCTUnwrap(touches(engine.pointerMoved(to: CGPoint(x: 0.5, y: 0.5), frameSize: phone)).first)
        XCTAssertGreaterThan(move.x, buttonX, "the mouse is to the right of this hero")
    }

    func testAKnownPointerAimsTheFingerAtOnce() throws {
        var engine = engine([skill()])
        _ = engine.pointerMoved(to: CGPoint(x: 0.9, y: 0.5), frameSize: phone)
        let actions = touches(engine.keyDown(keyQ, frameSize: phone))
        XCTAssertEqual(actions.map(\.action), [.down, .move], "down on the button, then straight to the aimed spot")
        XCTAssertGreaterThan(actions[1].x, buttonX)
        XCTAssertEqual(touches(engine.keyUp(keyQ, frameSize: phone)).first?.x ?? 0, actions[1].x, accuracy: 0.1, "cast where it was aimed")
    }

    func testNoMovesWhenTheAimDidNotChange() {
        var engine = engine([skill()])
        _ = engine.keyDown(keyQ, frameSize: phone)
        XCTAssertFalse(engine.pointerMoved(to: CGPoint(x: 0.7, y: 0.5), frameSize: phone).isEmpty)
        XCTAssertTrue(engine.pointerMoved(to: CGPoint(x: 0.7, y: 0.5), frameSize: phone).isEmpty)
    }

    func testPointerMovesDoNothingWhenNoSkillIsHeld() {
        var engine = engine([skill()])
        XCTAssertEqual(engine.pointerMoved(to: CGPoint(x: 0.9, y: 0.1), frameSize: phone), [])
    }

    func testQuickCastTapsTowardsTheMouseInOnePress() throws {
        var engine = engine([skill(cast: .instant)])
        _ = engine.pointerMoved(to: CGPoint(x: 0.9, y: 0.5), frameSize: phone)

        let actions = engine.keyDown(keyQ, frameSize: phone)
        XCTAssertEqual(touches(actions).map(\.action), [.down, .move, .up])
        guard case let .sendAfter(delay, _, slot) = actions.last else { return XCTFail("the lift must be delayed") }
        XCTAssertEqual(delay, KeymapEngine.tapDuration)
        XCTAssertEqual(touches(actions)[2].x, touches(actions)[1].x, accuracy: 0.1)

        XCTAssertEqual(engine.keyUp(keyQ, frameSize: phone), [], "letting go does nothing for a quick cast")
        engine.finishTap(slot: slot)
    }

    func testTwoSkillsHeldTogetherUseDifferentFingersAndBothFollowTheMouse() throws {
        var engine = engine([skill(keyQ, x: 0.8), skill(keyE, x: 0.7)])
        let first = try XCTUnwrap(touches(engine.keyDown(keyQ, frameSize: phone)).first)
        let second = try XCTUnwrap(touches(engine.keyDown(keyE, frameSize: phone)).first)
        XCTAssertNotEqual(first.slot, second.slot)
        XCTAssertEqual(touches(engine.pointerMoved(to: CGPoint(x: 0.9, y: 0.5), frameSize: phone)).count, 2)
    }

    func testReleaseAllLiftsAHeldSkillWhereItIs() throws {
        var engine = engine([skill()])
        _ = engine.keyDown(keyQ, frameSize: phone)
        let moved = try XCTUnwrap(touches(engine.pointerMoved(to: CGPoint(x: 0.9, y: 0.5), frameSize: phone)).first)
        let lifted = touches(engine.releaseAll(frameSize: phone))
        XCTAssertEqual(lifted.map(\.action), [.up])
        XCTAssertEqual(lifted[0].x, moved.x, accuracy: 0.1)
        XCTAssertEqual(engine.keyUp(keyQ, frameSize: phone), [])
    }

    func testPressingAHeldSkillAgainIsIgnored() {
        var engine = engine([skill()])
        _ = engine.keyDown(keyQ, frameSize: phone)
        XCTAssertEqual(engine.keyDown(keyQ, frameSize: phone), [], "auto-repeat")
    }
}

final class SkillShotModelTests: XCTestCase {
    func testValidationClampsNumbersAndTheHeroPosition() throws {
        let checked = try Keymap(elements: [skill(radius: 9, range: 0, hero: NormalizedPoint(x: -3, y: 4))]).validated()
        guard case let .skillShot(_, _, radius, range, hero) = checked.elements[0].action else { return XCTFail() }
        XCTAssertEqual(radius, KeymapAction.radiusRange.upperBound)
        XCTAssertEqual(range, KeymapAction.skillRange.lowerBound)
        XCTAssertEqual(hero, NormalizedPoint(x: 0, y: 1))
    }

    func testValidationRejectsNonFiniteNumbers() {
        XCTAssertThrowsError(try Keymap(elements: [skill(radius: .nan)]).validated()) { XCTAssertEqual($0 as? Keymap.Problem, .invalidSkillShot(label: "Skill")) }
        XCTAssertThrowsError(try Keymap(elements: [skill(range: .infinity)]).validated())
        XCTAssertThrowsError(try Keymap(elements: [skill(hero: NormalizedPoint(x: .nan, y: 0.5))]).validated())
    }

    func testSurvivesJSON() throws {
        let keymap = Keymap(elements: [skill(), skill(keyE, cast: .instant)])
        XCTAssertEqual(try JSONDecoder().decode(Keymap.self, from: try JSONEncoder().encode(keymap)), keymap)
    }
}

@MainActor
final class SkillShotControllerTests: XCTestCase {
    private final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [TouchAction] = []
        func add(_ message: ControlMessage) { if case let .touch(action, _, _, _) = message { lock.withLock { items.append(action) } } }
        var actions: [TouchAction] { lock.withLock { items } }
    }

    private func makeController(enabled: Bool = true) -> (KeymapController, Sent) {
        let sent = Sent()
        let controller = KeymapController(send: { sent.add($0) }, cursor: FakeCursorCapture())
        controller.updateFrameSize(CGSize(width: 1080, height: 2340))
        controller.load(Keymap(elements: [skill()]), profile: nil)
        controller.isEnabled = enabled
        return (controller, sent)
    }

    func testThePointerOnlyMattersWhileTheKeymapIsOn() {
        let (controller, sent) = makeController(enabled: false)
        controller.pointerMoved(to: CGPoint(x: 0.9, y: 0.5))
        XCTAssertTrue(sent.actions.isEmpty)
    }

    func testAimingAndCastingThroughTheController() {
        let (controller, sent) = makeController()
        XCTAssertTrue(controller.keyDown(keyQ))
        controller.pointerMoved(to: CGPoint(x: 0.9, y: 0.5))
        XCTAssertTrue(controller.keyUp(keyQ))
        XCTAssertEqual(sent.actions, [.down, .move, .up])
    }

    func testSwitchingOffInTheMiddleOfAimingLiftsTheFinger() {
        let (controller, sent) = makeController()
        _ = controller.keyDown(keyQ)
        controller.isEnabled = false
        XCTAssertEqual(sent.actions, [.down, .up])
    }
}
