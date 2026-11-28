import XCTest
import FeatureTestSupport
@testable import DomainModels
@testable import KeymapFeature

private let keyW: UInt16 = 13, keyA: UInt16 = 0, keyS: UInt16 = 1, keyD: UInt16 = 2, keySpace: UInt16 = 49

private func stick(x: Double = 0.5, y: Double = 0.5, radius: Double = 0.1, response: Double = 0.08, label: String = "") -> KeymapElement {
    KeymapElement(label: label, position: NormalizedPoint(x: x, y: y),
                  action: .joystick(up: keyW, left: keyA, down: keyS, right: keyD, radius: radius, response: response))
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

final class JoystickEngineTests: XCTestCase {
    private let phone = CGSize(width: 1080, height: 2340)
    private let centreX = 539.5, centreY = 1169.5, reach = 108.0

    func testFingerGoesDownAtTheCentreThenEasesToFullDeflection() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [stick()]))

        let pressed = touches(engine.keyDown(keyW, frameSize: phone))
        XCTAssertEqual(pressed.map(\.action), [.down])
        XCTAssertEqual(pressed[0].x, centreX, accuracy: 0.6)
        XCTAssertEqual(pressed[0].y, centreY, accuracy: 0.6)

        let half = touches(engine.tick(deltaTime: 0.04, frameSize: phone))
        XCTAssertEqual(half.map(\.action), [.move])
        XCTAssertEqual(half[0].y, centreY - reach / 2, accuracy: 1.1)
        XCTAssertEqual(half[0].x, centreX, accuracy: 0.6)

        let full = touches(engine.tick(deltaTime: 0.04, frameSize: phone))
        XCTAssertEqual(full[0].y, centreY - reach, accuracy: 1.1)

        XCTAssertEqual(engine.tick(deltaTime: 0.04, frameSize: phone), [], "holding steady sends nothing")
        XCTAssertTrue(engine.isAnimating)
    }

    func testDiagonalsAreNotFasterThanStraightLines() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [stick()]))
        _ = engine.keyDown(keyW, frameSize: phone)
        _ = engine.keyDown(keyD, frameSize: phone)
        let move = try XCTUnwrap(touches(engine.tick(deltaTime: 1, frameSize: phone)).last)
        let dx = move.x - centreX, dy = move.y - centreY
        XCTAssertEqual((dx * dx + dy * dy).squareRoot(), reach, accuracy: 1.5, "length is the radius, not radius × √2")
        XCTAssertGreaterThan(dx, 0)
        XCTAssertLessThan(dy, 0)
    }

    func testReleaseEasesBackToTheCentreThenLiftsThere() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [stick()]))
        _ = engine.keyDown(keyW, frameSize: phone)
        _ = engine.tick(deltaTime: 1, frameSize: phone)

        XCTAssertEqual(engine.keyUp(keyW, frameSize: phone), [], "the stick is still out; it has to come back first")
        let back = touches(engine.tick(deltaTime: 0.04, frameSize: phone))
        XCTAssertEqual(back.map(\.action), [.move])
        XCTAssertEqual(back[0].y, centreY - reach / 2, accuracy: 1.1)

        let done = touches(engine.tick(deltaTime: 0.04, frameSize: phone))
        XCTAssertEqual(done.map(\.action), [.up])
        XCTAssertEqual(done[0].y, centreY, accuracy: 0.6, "lifted at the centre, not mid-flick")
        XCTAssertFalse(engine.isAnimating)
        XCTAssertEqual(engine.tick(deltaTime: 0.1, frameSize: phone), [])
    }

    func testZeroResponseMovesInstantly() {
        var engine = KeymapEngine(keymap: Keymap(elements: [stick(response: 0)]))
        let actions = touches(engine.keyDown(keyA, frameSize: phone))
        XCTAssertEqual(actions.map(\.action), [.down, .move])
        XCTAssertEqual(actions[1].x, centreX - reach, accuracy: 1.1)
        let release = touches(engine.keyUp(keyA, frameSize: phone))
        XCTAssertEqual(release.map(\.action), [.up], "no response time: straight back to the centre and lifted")
        XCTAssertEqual(release[0].x, centreX, accuracy: 0.6)
        XCTAssertFalse(engine.isAnimating)
    }

    func testOppositeKeysCancelOut() {
        var engine = KeymapEngine(keymap: Keymap(elements: [stick()]))
        XCTAssertEqual(touches(engine.keyDown(keyW, frameSize: phone)).map(\.action), [.down])
        XCTAssertEqual(touches(engine.keyDown(keyS, frameSize: phone)).map(\.action), [.up], "net zero: the stick lifts")
        XCTAssertFalse(engine.isAnimating)
        XCTAssertEqual(touches(engine.keyUp(keyS, frameSize: phone)).map(\.action), [.down], "W is still held, so the stick engages again")
    }

    func testStickAndButtonsUseDifferentFingers() throws {
        let fire = KeymapElement(position: NormalizedPoint(x: 0.9, y: 0.9), action: .button(key: keySpace, mode: .hold))
        var engine = KeymapEngine(keymap: Keymap(elements: [stick(), fire]))
        let moving = try XCTUnwrap(touches(engine.keyDown(keyW, frameSize: phone)).first)
        let firing = try XCTUnwrap(touches(engine.keyDown(keySpace, frameSize: phone)).first)
        XCTAssertNotEqual(moving.slot, firing.slot)
    }

    func testReleaseAllLiftsTheStickWhereItIs() throws {
        var engine = KeymapEngine(keymap: Keymap(elements: [stick(response: 0)]))
        _ = engine.keyDown(keyW, frameSize: phone)
        let lifted = touches(engine.releaseAll(frameSize: phone))
        XCTAssertEqual(lifted.map(\.action), [.up])
        XCTAssertEqual(lifted[0].y, centreY - reach, accuracy: 1.1)
        XCTAssertFalse(engine.isAnimating)
        XCTAssertEqual(touches(engine.keyDown(keyW, frameSize: phone)).first?.slot, .slot(0), "the slot is free again")
    }

    func testReachFollowsTheShorterEdgeAndNeverLeavesTheScreen() throws {
        var landscape = KeymapEngine(keymap: Keymap(elements: [stick(radius: 0.1, response: 0)]))
        let wide = CGSize(width: 2340, height: 1080)
        let move = try XCTUnwrap(touches(landscape.keyDown(keyD, frameSize: wide)).last)
        XCTAssertEqual(move.x - 1169.5, reach, accuracy: 1.1, "same physical reach in landscape")

        var edge = KeymapEngine(keymap: Keymap(elements: [stick(x: 0.02, radius: 0.5, response: 0)]))
        let pushed = try XCTUnwrap(touches(edge.keyDown(keyA, frameSize: phone)).last)
        XCTAssertEqual(pushed.x, 0, "clamped to the left edge")
    }

    func testStickKeysAreHandledAndOthersAreNot() {
        let engine = KeymapEngine(keymap: Keymap(elements: [stick()]))
        for key in [keyW, keyA, keyS, keyD] { XCTAssertTrue(engine.handles(key)) }
        XCTAssertFalse(engine.handles(keySpace))
    }

    func testAutoRepeatDoesNotRestartTheStick() {
        var engine = KeymapEngine(keymap: Keymap(elements: [stick()]))
        _ = engine.keyDown(keyW, frameSize: phone)
        XCTAssertEqual(engine.keyDown(keyW, frameSize: phone), [])
    }
}

final class JoystickModelTests: XCTestCase {
    func testValidationClampsRadiusAndResponse() throws {
        let checked = try Keymap(elements: [stick(radius: 9, response: -3)]).validated()
        guard case let .joystick(_, _, _, _, radius, response) = checked.elements[0].action else { return XCTFail() }
        XCTAssertEqual(radius, KeymapAction.radiusRange.upperBound)
        XCTAssertEqual(response, KeymapAction.responseRange.lowerBound)
    }

    func testValidationRejectsRepeatedKeysAndBadNumbers() {
        let repeated = KeymapElement(label: "Move", position: NormalizedPoint(x: 0.2, y: 0.8),
                                     action: .joystick(up: keyW, left: keyW, down: keyS, right: keyD, radius: 0.1, response: 0.1))
        XCTAssertThrowsError(try Keymap(elements: [repeated]).validated()) { XCTAssertEqual($0 as? Keymap.Problem, .invalidJoystick(label: "Move")) }
        XCTAssertThrowsError(try Keymap(elements: [stick(radius: .nan)]).validated())
        XCTAssertThrowsError(try Keymap(elements: [stick(response: .infinity)]).validated())
    }

    func testJoystickSurvivesJSON() throws {
        let keymap = Keymap(elements: [stick(x: 0.15, y: 0.75, radius: 0.12, response: 0.08, label: "Move")])
        let data = try JSONEncoder().encode(keymap)
        XCTAssertEqual(try JSONDecoder().decode(Keymap.self, from: data), keymap)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("joystick"))
    }
}

@MainActor
final class JoystickControllerTests: XCTestCase {
    private final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [TouchAction] = []
        func add(_ message: ControlMessage) { if case let .touch(action, _, _, _) = message { lock.withLock { items.append(action) } } }
        var actions: [TouchAction] { lock.withLock { items } }
    }

    func testTheClockMovesTheStickAndStopsWhenItIsBackAtTheCentre() async throws {
        let sent = Sent()
        let controller = KeymapController(send: { sent.add($0) }, cursor: FakeCursorCapture())
        controller.updateFrameSize(CGSize(width: 1080, height: 2340))
        controller.load(Keymap(elements: [stick(response: 0.05)]), profile: nil)
        controller.isEnabled = true

        XCTAssertTrue(controller.keyDown(keyW))
        let deadline = Date().addingTimeInterval(5)
        while sent.actions.filter({ $0 == .move }).count < 2, Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(sent.actions.first, .down)
        XCTAssertGreaterThanOrEqual(sent.actions.filter { $0 == .move }.count, 2, "moved in several steps, not one jump")

        XCTAssertTrue(controller.keyUp(keyW))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(sent.actions.last, .up)

        let finished = sent.actions.count
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(sent.actions.count, finished, "the clock stops once the stick is lifted")
    }

    func testSwitchingTheKeymapOffLiftsTheStick() async throws {
        let sent = Sent()
        let controller = KeymapController(send: { sent.add($0) }, cursor: FakeCursorCapture())
        controller.updateFrameSize(CGSize(width: 1080, height: 2340))
        controller.load(Keymap(elements: [stick(response: 0)]), profile: nil)
        controller.isEnabled = true
        _ = controller.keyDown(keyD)
        controller.isEnabled = false
        XCTAssertEqual(sent.actions.last, .up)
        let count = sent.actions.count
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(sent.actions.count, count, "no stray moves after the keymap is off")
    }
}
