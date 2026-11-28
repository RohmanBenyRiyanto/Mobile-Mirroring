import XCTest
import FeatureTestSupport
@testable import DomainModels
@testable import KeymapFeature
@testable import Persistence

private let keyQ: UInt16 = 12

private func position(_ x: Int32, _ y: Int32, frame: (UInt16, UInt16) = (1080, 2340)) -> TouchPosition {
    TouchPosition(x: x, y: y, frameWidth: frame.0, frameHeight: frame.1)
}

private func message(_ action: TouchAction, _ x: Int32, _ y: Int32, pointer: PointerID = .mouse) -> ControlMessage {
    .touch(action, position(x, y), pressure: action == .up ? 0 : 1, pointer: pointer)
}

private func step(_ time: Double, _ kind: MacroStep.Kind, finger: Int = 0, x: Double, y: Double) -> MacroStep {
    MacroStep(time: time, kind: kind, finger: finger, position: NormalizedPoint(x: x, y: y))
}

private func macro(_ steps: [MacroStep], loop: Bool = false, speed: Double = 1) -> KeymapElement {
    KeymapElement(label: "Macro", position: NormalizedPoint(x: 0.5, y: 0.5),
                  action: .macro(key: keyQ, steps: steps, loop: loop, speed: speed))
}

final class MacroRecorderTests: XCTestCase {
    func testRecordsATouchWithRelativeTimesAndRatios() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.observe(message(.down, 0, 0), at: 100.0)
        recorder.observe(message(.move, 540, 1170), at: 100.25)
        recorder.observe(message(.up, 1079, 2339), at: 100.5)

        let steps = recorder.stop()
        XCTAssertEqual(steps.map(\.kind), [.down, .move, .up])
        XCTAssertEqual(steps.map(\.time), [0, 0.25, 0.5])
        XCTAssertEqual(steps[0].position, NormalizedPoint(x: 0, y: 0))
        XCTAssertEqual(steps[1].position.x, 540.0 / 1079, accuracy: 1e-9)
        XCTAssertEqual(steps[2].position, NormalizedPoint(x: 1, y: 1))
        XCTAssertFalse(recorder.isRecording)
    }

    func testTimeStartsAtTheFirstTouchNotAtTheStartOfRecording() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.observe(message(.down, 10, 10), at: 50)
        recorder.observe(message(.up, 10, 10), at: 50.1)
        XCTAssertEqual(recorder.stop().map { ($0.time * 1000).rounded() / 1000 }, [0, 0.1])
    }

    func testNumbersFingersInOrderAndReusesFreedNumbers() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.observe(message(.down, 1, 1, pointer: .slot(3)), at: 0)
        recorder.observe(message(.down, 2, 2, pointer: .slot(7)), at: 0.1)
        recorder.observe(message(.up, 1, 1, pointer: .slot(3)), at: 0.2)
        recorder.observe(message(.down, 3, 3, pointer: .slot(5)), at: 0.3)

        let steps = recorder.stop()
        XCTAssertEqual(steps.filter { $0.kind == .down }.map(\.finger), [0, 1, 0], "phone pointer ids become 0, 1, … and a freed number is reused")
        XCTAssertEqual(steps.map(\.kind), [.down, .down, .up, .down, .up, .up], "the two fingers still down are lifted at the end")
        XCTAssertEqual(steps.map(\.finger), [0, 1, 0, 0, 0, 1])
    }

    func testIgnoresEverythingButTouchesAndOnlyWhileRecording() {
        let recorder = MacroRecorder()
        recorder.observe(message(.down, 1, 1), at: 0)
        recorder.start()
        recorder.observe(.keycode(.down, .home), at: 0)
        recorder.observe(.scroll(position(1, 1), horizontal: 1, vertical: 1), at: 0)
        recorder.observe(message(.move, 5, 5), at: 0.1)
        XCTAssertEqual(recorder.stop(), [])
    }

    func testRepeatedMovesToTheSameSpotAreDropped() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.observe(message(.down, 5, 5), at: 0)
        recorder.observe(message(.move, 5, 5), at: 0.01)
        recorder.observe(message(.move, 9, 9), at: 0.02)
        recorder.observe(message(.move, 9, 9), at: 0.03)
        recorder.observe(message(.up, 9, 9), at: 0.04)
        XCTAssertEqual(recorder.stop().map(\.kind), [.down, .move, .up])
    }

    func testAFingerStillDownIsLiftedWhereItWasWhenRecordingStops() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.observe(message(.down, 100, 200), at: 0)
        recorder.observe(message(.move, 300, 400), at: 0.5)
        let steps = recorder.stop()
        XCTAssertEqual(steps.last?.kind, .up)
        XCTAssertEqual(steps.last?.time, 0.5)
        XCTAssertEqual(steps.last?.position, steps[1].position)
    }

    func testStopsGrowingAtTheLimits() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.observe(message(.down, 1, 1), at: 0)
        recorder.observe(message(.move, 2, 2), at: KeymapAction.maxMacroDuration + 1)
        XCTAssertEqual(recorder.stop().filter { $0.kind == .move }.count, 0, "too long")

        recorder.start()
        recorder.observe(message(.down, 1, 1), at: 0)
        for index in 0..<(KeymapAction.maxMacroSteps + 50) {
            recorder.observe(message(.move, Int32(index % 1000), 7), at: Double(index) * 0.001)
        }
        XCTAssertLessThanOrEqual(recorder.stop().count, KeymapAction.maxMacroSteps + 1, "the one lift added at the end")
    }

    func testCanRecordAgainAfterStopping() {
        let recorder = MacroRecorder()
        recorder.start()
        recorder.observe(message(.down, 1, 1), at: 0)
        _ = recorder.stop()
        recorder.start()
        recorder.observe(message(.down, 2, 2), at: 9)
        recorder.observe(message(.up, 2, 2), at: 9.2)
        XCTAssertEqual(recorder.stop().map { ($0.time * 1000).rounded() / 1000 }, [0, 0.2])
    }
}

final class MacroEngineTests: XCTestCase {
    private let phone = CGSize(width: 1080, height: 2340)

    private struct Seen: Equatable {
        let action: TouchAction
        let x: Int32
        let slot: PointerID
    }

    private func seen(_ actions: [KeymapEngine.Action]) -> [Seen] {
        actions.compactMap { action in
            guard case let .send(.touch(kind, position, _, pointer)) = action else { return nil }
            return Seen(action: kind, x: position.x, slot: pointer)
        }
    }

    private var swipe: [MacroStep] {
        [step(0, .down, x: 0.1, y: 0.5), step(0.1, .move, x: 0.5, y: 0.5), step(0.2, .up, x: 0.9, y: 0.5)]
    }

    func testPlaysEachStepAtItsTime() {
        var engine = KeymapEngine(keymap: Keymap(elements: [macro(swipe)]))

        XCTAssertEqual(seen(engine.keyDown(keyQ, frameSize: phone)).map(\.action), [.down], "the step at time 0 plays at once")
        XCTAssertTrue(engine.isAnimating)
        XCTAssertEqual(engine.tick(deltaTime: 0.05, frameSize: phone), [], "nothing is due yet")
        XCTAssertEqual(seen(engine.tick(deltaTime: 0.06, frameSize: phone)).map(\.action), [.move])
        XCTAssertEqual(engine.tick(deltaTime: 0.05, frameSize: phone), [])
        let last = seen(engine.tick(deltaTime: 0.05, frameSize: phone))
        XCTAssertEqual(last.map(\.action), [.up])
        XCTAssertEqual(Double(last[0].x), 0.9 * 1079, accuracy: 0.6)
        XCTAssertFalse(engine.isAnimating, "finished")
    }

    func testSeveralStepsDueInOneTickPlayInOrder() {
        var engine = KeymapEngine(keymap: Keymap(elements: [macro(swipe)]))
        _ = engine.keyDown(keyQ, frameSize: phone)
        XCTAssertEqual(seen(engine.tick(deltaTime: 1, frameSize: phone)).map(\.action), [.move, .up])
    }

    func testSpeedScalesTime() {
        var engine = KeymapEngine(keymap: Keymap(elements: [macro(swipe, speed: 2)]))
        _ = engine.keyDown(keyQ, frameSize: phone)
        XCTAssertEqual(seen(engine.tick(deltaTime: 0.05, frameSize: phone)).map(\.action), [.move], "twice as fast: the 0.1 s step is due after 0.05 s")
    }

    func testTwoFingersKeepTheirOwnSlots() {
        let steps = [step(0, .down, finger: 0, x: 0.2, y: 0.5), step(0, .down, finger: 1, x: 0.8, y: 0.5),
                     step(0.1, .move, finger: 0, x: 0.3, y: 0.5), step(0.1, .move, finger: 1, x: 0.7, y: 0.5),
                     step(0.2, .up, finger: 0, x: 0.3, y: 0.5), step(0.2, .up, finger: 1, x: 0.7, y: 0.5)]
        var engine = KeymapEngine(keymap: Keymap(elements: [macro(steps)]))
        let downs = seen(engine.keyDown(keyQ, frameSize: phone))
        XCTAssertEqual(downs.count, 2)
        XCTAssertNotEqual(downs[0].slot, downs[1].slot)
        let moves = seen(engine.tick(deltaTime: 0.1, frameSize: phone))
        XCTAssertEqual(moves.map(\.slot), downs.map(\.slot))
        let ups = seen(engine.tick(deltaTime: 0.1, frameSize: phone))
        XCTAssertEqual(ups.map(\.slot), downs.map(\.slot))
    }

    func testPressingAgainWhilePlayingDoesNotRestartIt() {
        var engine = KeymapEngine(keymap: Keymap(elements: [macro(swipe)]))
        _ = engine.keyDown(keyQ, frameSize: phone)
        _ = engine.keyUp(keyQ, frameSize: phone)
        XCTAssertEqual(engine.keyDown(keyQ, frameSize: phone), [])
        XCTAssertEqual(engine.keyUp(keyQ, frameSize: phone), [], "a one-shot macro plays on after the key is released")
        XCTAssertTrue(engine.isAnimating)
    }

    func testALoopingMacroRepeatsWhileHeldAndStopsOnRelease() {
        var engine = KeymapEngine(keymap: Keymap(elements: [macro(swipe, loop: true)]))
        var all = seen(engine.keyDown(keyQ, frameSize: phone))
        for _ in 0..<10 { all += seen(engine.tick(deltaTime: 0.1, frameSize: phone)) }
        XCTAssertGreaterThanOrEqual(all.filter { $0.action == .down }.count, 4)
        XCTAssertEqual(all.filter { $0.action == .down }.count - all.filter { $0.action == .up }.count, all.last?.action == .up ? 0 : 1)

        let ending = seen(engine.keyUp(keyQ, frameSize: phone))
        XCTAssertFalse(engine.isAnimating)
        XCTAssertTrue(ending.allSatisfy { $0.action == .up }, "releasing lifts any finger still down")
        XCTAssertEqual(engine.tick(deltaTime: 0.5, frameSize: phone), [])
    }

    func testReleaseAllCancelsAndLiftsTheFingersThatAreDown() {
        var engine = KeymapEngine(keymap: Keymap(elements: [macro(swipe)]))
        _ = engine.keyDown(keyQ, frameSize: phone)
        _ = engine.tick(deltaTime: 0.12, frameSize: phone)

        let lifted = seen(engine.releaseAll(frameSize: phone))
        XCTAssertEqual(lifted.map(\.action), [.up])
        XCTAssertFalse(engine.isAnimating)
        XCTAssertEqual(engine.tick(deltaTime: 1, frameSize: phone), [], "the rest of the macro never plays")
    }

    func testSlotsAreFreeAgainAfterAMacro() {
        var engine = KeymapEngine(keymap: Keymap(elements: [macro(swipe)]))
        _ = engine.keyDown(keyQ, frameSize: phone)
        _ = engine.tick(deltaTime: 1, frameSize: phone)
        _ = engine.keyUp(keyQ, frameSize: phone)
        XCTAssertEqual(seen(engine.keyDown(keyQ, frameSize: phone)).first?.slot, .slot(0))
    }

    func testAFingerWithNoFreeSlotIsSkippedWithoutBreakingTheRest() {
        let holds = (0..<10).map { KeymapElement(position: NormalizedPoint(x: 0.5, y: 0.5), action: .button(key: UInt16(100 + $0), mode: .hold)) }
        var engine = KeymapEngine(keymap: Keymap(elements: holds + [macro(swipe)]))
        for index in 0..<10 { _ = engine.keyDown(UInt16(100 + index), frameSize: phone) }
        XCTAssertEqual(engine.keyDown(keyQ, frameSize: phone), [])
        XCTAssertEqual(engine.tick(deltaTime: 1, frameSize: phone), [], "its moves and lift are skipped too")
        XCTAssertFalse(engine.isAnimating)
    }

    func testARecordingThatEndedWithAFingerDownIsLiftedAtTheEnd() {
        var engine = KeymapEngine(keymap: Keymap(elements: [macro([step(0, .down, x: 0.5, y: 0.5), step(0.1, .move, x: 0.6, y: 0.5)])]))
        _ = engine.keyDown(keyQ, frameSize: phone)
        XCTAssertEqual(seen(engine.tick(deltaTime: 0.2, frameSize: phone)).map(\.action), [.move, .up])
    }

    func testRecordedTouchesPlayBackIdentically() throws {
        let original: [(TouchAction, Int32, Int32, Double)] = [(.down, 100, 2000, 0), (.move, 300, 1700, 0.05), (.move, 600, 1200, 0.12),
                                                               (.move, 900, 800, 0.2), (.up, 900, 800, 0.25)]
        let recorder = MacroRecorder()
        recorder.start()
        for (action, x, y, time) in original { recorder.observe(message(action, x, y, pointer: .slot(4)), at: 10 + time) }
        let element = try Keymap(elements: [macro(recorder.stop())]).validated().elements[0]

        var engine = KeymapEngine(keymap: Keymap(elements: [element]))
        var played = seen(engine.keyDown(keyQ, frameSize: phone))
        var clock = 0.0
        while engine.isAnimating, clock < 2 {
            played += seen(engine.tick(deltaTime: 0.01, frameSize: phone))
            clock += 0.01
        }
        XCTAssertEqual(played.map(\.action), original.map(\.0))
        for (index, expected) in original.enumerated() {
            XCTAssertEqual(Double(played[index].x), Double(expected.1), accuracy: 1.1, "step \(index)")
        }
    }
}

final class MacroModelTests: XCTestCase {
    func testValidationSortsStepsAndClampsPositions() throws {
        let checked = try Keymap(elements: [macro([step(0.2, .up, x: 2, y: -1), step(0, .down, x: 0.5, y: 0.5)], speed: 99)]).validated()
        guard case let .macro(_, steps, _, speed) = checked.elements[0].action else { return XCTFail() }
        XCTAssertEqual(steps.map(\.time), [0, 0.2])
        XCTAssertEqual(steps[1].position, NormalizedPoint(x: 1, y: 0))
        XCTAssertEqual(speed, KeymapAction.macroSpeedRange.upperBound)
    }

    func testValidationRejectsBrokenMacros() {
        let bad: [[MacroStep]] = [
            [],
            [step(.nan, .down, x: 0.5, y: 0.5)],
            [step(-1, .down, x: 0.5, y: 0.5)],
            [step(KeymapAction.maxMacroDuration + 1, .down, x: 0.5, y: 0.5)],
            [step(0, .down, finger: 10, x: 0.5, y: 0.5)],
            [step(0, .down, x: .nan, y: 0.5)],
            Array(repeating: step(0, .move, x: 0.5, y: 0.5), count: KeymapAction.maxMacroSteps + 1),
        ]
        for steps in bad {
            XCTAssertThrowsError(try Keymap(elements: [macro(steps)]).validated(), "\(steps.count) steps") {
                XCTAssertEqual($0 as? Keymap.Problem, .invalidMacro(label: "Macro"))
            }
        }
        XCTAssertThrowsError(try Keymap(elements: [macro([step(0, .down, x: 0.5, y: 0.5)], speed: .nan)]).validated())
    }

    func testMacroSurvivesJSONAndTheProfileStore() throws {
        let keymap = Keymap(elements: [macro([step(0, .down, x: 0.1, y: 0.2), step(0.5, .up, x: 0.3, y: 0.4)], loop: true, speed: 1.5)])
        XCTAssertEqual(try JSONDecoder().decode(Keymap.self, from: try JSONEncoder().encode(keymap)), keymap)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProfileStore<Keymap>(kind: "keymap", root: root)
        try store.save(Profile(id: "m", name: "M", payload: keymap))
        XCTAssertEqual(try store.load(id: "m").payload, keymap)
    }
}

@MainActor
final class MacroControllerTests: XCTestCase {
    private final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [TouchAction] = []
        func add(_ message: ControlMessage) { if case let .touch(action, _, _, _) = message { lock.withLock { items.append(action) } } }
        var actions: [TouchAction] { lock.withLock { items } }
    }

    func testTheClockPlaysAMacroInRealTime() async throws {
        let sent = Sent()
        let controller = KeymapController(send: { sent.add($0) }, cursor: FakeCursorCapture())
        controller.updateFrameSize(CGSize(width: 1080, height: 2340))
        controller.load(Keymap(elements: [macro([step(0, .down, x: 0.2, y: 0.5), step(0.08, .move, x: 0.5, y: 0.5), step(0.16, .up, x: 0.8, y: 0.5)])]), profile: nil)
        controller.isEnabled = true

        XCTAssertTrue(controller.keyDown(keyQ))
        XCTAssertEqual(sent.actions, [.down])
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(sent.actions, [.down, .move, .up])
    }

    func testSwitchingTheKeymapOffMidMacroLiftsTheFinger() async throws {
        let sent = Sent()
        let controller = KeymapController(send: { sent.add($0) }, cursor: FakeCursorCapture())
        controller.updateFrameSize(CGSize(width: 1080, height: 2340))
        controller.load(Keymap(elements: [macro([step(0, .down, x: 0.2, y: 0.5), step(1, .up, x: 0.8, y: 0.5)])]), profile: nil)
        controller.isEnabled = true
        _ = controller.keyDown(keyQ)
        controller.isEnabled = false
        XCTAssertEqual(sent.actions, [.down, .up])
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(sent.actions.count, 2, "the rest of the macro was cancelled")
    }
}
