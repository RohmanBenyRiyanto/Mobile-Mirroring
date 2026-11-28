import Foundation

/// A button or stick direction on a game controller. A keymap can bind each to a keyboard key it already uses,
/// so the same buttons on screen are driven by the controller too.
public enum GamepadInput: String, CaseIterable, Codable, Identifiable, Sendable {
    case buttonA, buttonB, buttonX, buttonY
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case leftStickUp, leftStickDown, leftStickLeft, leftStickRight
    case rightStickUp, rightStickDown, rightStickLeft, rightStickRight
    case leftStickButton, rightStickButton, menu, options

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .buttonA: return "A"
        case .buttonB: return "B"
        case .buttonX: return "X"
        case .buttonY: return "Y"
        case .leftShoulder: return "Left bumper"
        case .rightShoulder: return "Right bumper"
        case .leftTrigger: return "Left trigger"
        case .rightTrigger: return "Right trigger"
        case .dpadUp: return "D-pad up"
        case .dpadDown: return "D-pad down"
        case .dpadLeft: return "D-pad left"
        case .dpadRight: return "D-pad right"
        case .leftStickUp: return "Left stick up"
        case .leftStickDown: return "Left stick down"
        case .leftStickLeft: return "Left stick left"
        case .leftStickRight: return "Left stick right"
        case .rightStickUp: return "Right stick up"
        case .rightStickDown: return "Right stick down"
        case .rightStickLeft: return "Right stick left"
        case .rightStickRight: return "Right stick right"
        case .leftStickButton: return "Left stick press"
        case .rightStickButton: return "Right stick press"
        case .menu: return "Menu"
        case .options: return "Options"
        }
    }
}

/// Turns an analog stick position into pressed directions. A direction presses past 0.5 and releases below 0.3, so a stick resting near the
/// edge does not flicker.
public struct StickDirections: Equatable, Sendable {
    public struct Pressed: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let up = Pressed(rawValue: 1), down = Pressed(rawValue: 2), left = Pressed(rawValue: 4), right = Pressed(rawValue: 8)
    }

    public static let pressAt = 0.5
    public static let releaseAt = 0.3

    public static func update(x: Double, y: Double, previous: Pressed) -> Pressed {
        func axis(_ value: Double, negative: Pressed, positive: Pressed) -> Pressed {
            var result: Pressed = []
            if value > pressAt || (previous.contains(positive) && value > releaseAt) { result.insert(positive) }
            if value < -pressAt || (previous.contains(negative) && value < -releaseAt) { result.insert(negative) }
            return result
        }
        // GameController reports up as positive y.
        return axis(x, negative: .left, positive: .right).union(axis(y, negative: .down, positive: .up))
    }
}

extension Keymap {
    public static let maxGamepadBindings = 32

    /// The keyboard key a controller input stands for in this keymap, if it is bound.
    public func key(for input: GamepadInput) -> UInt16? { gamepad?[input.rawValue] }

    /// Drops bindings that name an unknown button, a key outside the keyboard range, or too many entries.
    func cleanedGamepad() -> [String: UInt16]? {
        guard let gamepad else { return nil }
        let valid = gamepad.filter { GamepadInput(rawValue: $0.key) != nil && $0.value <= 255 }
        return valid.isEmpty ? nil : Dictionary(uniqueKeysWithValues: valid.sorted { $0.key < $1.key }.prefix(Self.maxGamepadBindings).map { ($0.key, $0.value) })
    }
}
