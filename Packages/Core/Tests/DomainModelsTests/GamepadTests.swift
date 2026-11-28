import XCTest
@testable import DomainModels

final class GamepadTests: XCTestCase {
    func testStickDirectionsHaveHysteresis() {
        var state = StickDirections.update(x: 0.6, y: 0, previous: [])
        XCTAssertEqual(state, .right)
        state = StickDirections.update(x: 0.4, y: 0, previous: state)
        XCTAssertEqual(state, .right, "between the two thresholds it stays pressed")
        state = StickDirections.update(x: 0.2, y: 0, previous: state)
        XCTAssertEqual(state, [])
        XCTAssertEqual(StickDirections.update(x: -0.7, y: 0.9, previous: []), [.left, .up])
    }

    func testKeymapGamepadBindingsAreCleanedAndRoundTrip() throws {
        var keymap = Keymap(package: "com.example.game")
        keymap.gamepad = ["buttonA": 18, "nonsense": 5, "buttonB": 9999]
        let checked = try keymap.validated()
        XCTAssertEqual(checked.gamepad, ["buttonA": 18])
        XCTAssertEqual(checked.key(for: .buttonA), 18)
        XCTAssertNil(checked.key(for: .buttonX))

        let decoded = try JSONDecoder().decode(Keymap.self, from: JSONEncoder().encode(checked))
        XCTAssertEqual(decoded.gamepad, checked.gamepad)
        let old = try JSONDecoder().decode(Keymap.self, from: Data(#"{"elements":[]}"#.utf8))
        XCTAssertNil(old.gamepad, "keymaps saved before controllers existed still load")
    }

    func testEveryInputHasATitleAndTheNamesAreUnique() {
        XCTAssertEqual(Set(GamepadInput.allCases.map(\.title)).count, GamepadInput.allCases.count)
    }
}
