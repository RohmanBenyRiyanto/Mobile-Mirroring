import XCTest
@testable import DomainModels

private let keyQ: UInt16 = 12
private let frame = CGSize(width: 1080, height: 2340)

private func touches(_ actions: [KeymapEngine.Action]) -> [(TouchAction, Int32, Int32)] {
    actions.compactMap { action in
        if case let .send(.touch(kind, position, _, _)) = action { return (kind, position.x, position.y) }
        return nil
    }
}

final class TurboAndSwipeTests: XCTestCase {
    func testRapidTapRepeatsWhileHeldAtTheChosenRateAndStopsOnRelease() {
        var engine = KeymapEngine(keymap: Keymap(elements: [KeymapElement(position: NormalizedPoint(x: 0.5, y: 0.5), action: .turbo(key: keyQ, rate: 10))]))
        var all = touches(engine.keyDown(keyQ, frameSize: frame))
        for _ in 0..<60 { all += touches(engine.tick(deltaTime: 1.0 / 60, frameSize: frame)) } // one second
        let downs = all.filter { $0.0 == .down }.count
        let ups = all.filter { $0.0 == .up }.count
        XCTAssertTrue((9...11).contains(downs), "about ten taps in a second, got \(downs)")
        XCTAssertTrue(abs(downs - ups) <= 1, "every tap is lifted")
        XCTAssertTrue(all.allSatisfy { $0.1 == 540 && $0.2 == 1170 }, "always at the element's spot")

        let end = touches(engine.keyUp(keyQ, frameSize: frame)) + touches(engine.tick(deltaTime: 1, frameSize: frame))
        XCTAssertEqual(end.filter { $0.0 == .down }.count, 0, "nothing new after the key is released")
        XCTAssertFalse(engine.isAnimating)
    }

    func testSwipeGoesFromTheElementToTheEndOnceAndLifts() {
        var engine = KeymapEngine(keymap: Keymap(elements: [KeymapElement(position: NormalizedPoint(x: 0.5, y: 0.8),
                                                                           action: .swipe(key: keyQ, to: NormalizedPoint(x: 0.5, y: 0.2), duration: 0.25))]))
        var all = touches(engine.keyDown(keyQ, frameSize: frame))
        _ = engine.keyUp(keyQ, frameSize: frame) // releasing early does not cut the swipe short
        for _ in 0..<30 { all += touches(engine.tick(deltaTime: 1.0 / 60, frameSize: frame)) }
        XCTAssertEqual(all.first?.0, .down)
        XCTAssertEqual(all.last?.0, .up)
        XCTAssertEqual(Double(all.first?.2 ?? 0), 0.8 * 2339, accuracy: 3)
        XCTAssertEqual(Double(all.last?.2 ?? 0), 0.2 * 2339, accuracy: 3)
        let ys = all.filter { $0.0 == .move }.map(\.2)
        XCTAssertEqual(ys, ys.sorted(by: >), "the finger only moves towards the end")
        XCTAssertTrue(ys.count >= 10, "a smooth path, not a jump")
        XCTAssertFalse(engine.isAnimating)
    }

    func testValidationClampsAndRoundTrips() throws {
        let keymap = Keymap(elements: [
            KeymapElement(position: NormalizedPoint(x: 0.5, y: 0.5), action: .turbo(key: 1, rate: 500)),
            KeymapElement(position: NormalizedPoint(x: 0.1, y: 0.1), action: .swipe(key: 2, to: NormalizedPoint(x: 3, y: -1), duration: 99)),
        ])
        let checked = try keymap.validated()
        XCTAssertEqual(checked.elements[0].action, .turbo(key: 1, rate: 30))
        XCTAssertEqual(checked.elements[1].action, .swipe(key: 2, to: NormalizedPoint(x: 1, y: 0), duration: 2))
        XCTAssertEqual(try JSONDecoder().decode(Keymap.self, from: JSONEncoder().encode(checked)), checked)
        XCTAssertThrowsError(try Keymap(elements: [KeymapElement(position: NormalizedPoint(x: 0.5, y: 0.5), action: .turbo(key: 1, rate: .nan))]).validated())
    }
}
