import CoreGraphics
import Foundation
import Persistence

public struct NormalizedPoint: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
    public var clamped: NormalizedPoint { NormalizedPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1)) }
    public var isFinite: Bool { x.isFinite && y.isFinite }
}

public enum ButtonMode: String, Codable, CaseIterable, Identifiable {
    case tap
    case hold
    case toggle

    public var id: String { rawValue }
}

public struct MacroStep: Codable, Equatable {
    public enum Kind: String, Codable { case down, move, up }

    public var time: Double
    public var kind: Kind
    public var finger: Int
    public var position: NormalizedPoint

    public init(time: Double, kind: Kind, finger: Int, position: NormalizedPoint) {
        self.time = time
        self.kind = kind
        self.finger = finger
        self.position = position
    }
}

public enum SkillCast: String, Codable, CaseIterable, Identifiable {
    case onRelease
    case instant

    public var id: String { rawValue }
}

public enum KeymapAction: Codable, Equatable {
    case button(key: UInt16, mode: ButtonMode)
    case joystick(up: UInt16, left: UInt16, down: UInt16, right: UInt16, radius: Double, response: Double)

    case aim(toggleKey: UInt16, sensitivity: Double, radius: Double)
    case mouseButton(button: Int, mode: ButtonMode)

    case skillShot(key: UInt16, cast: SkillCast, radius: Double, range: Double, hero: NormalizedPoint)

    case macro(key: UInt16, steps: [MacroStep], loop: Bool, speed: Double)

    case turbo(key: UInt16, rate: Double)

    case swipe(key: UInt16, to: NormalizedPoint, duration: Double)

    public static let maxMacroSteps = 5_000
    public static let maxMacroDuration = 120.0
    public static let macroSpeedRange = 0.1...5.0
    public static let turboRateRange = 1.0...30.0
    public static let swipeDurationRange = 0.05...2.0

    public static let radiusRange = 0.02...0.5
    public static let skillRange = 0.05...1.0
    public static let responseRange = 0.0...1.0
    public static let sensitivityRange = 0.1...20.0
    public static let mouseButtons = 0...4
}

public struct KeymapElement: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var label = ""
    public var position: NormalizedPoint
    public var action: KeymapAction

    public init(id: UUID = UUID(), label: String = "", position: NormalizedPoint, action: KeymapAction) {
        self.id = id
        self.label = label
        self.position = position
        self.action = action
    }

    public var keys: [UInt16] {
        switch action {
        case let .button(key, _): return [key]
        case let .joystick(up, left, down, right, _, _): return [up, left, down, right]
        case let .aim(toggleKey, _, _): return [toggleKey]
        case .mouseButton: return []
        case let .skillShot(key, _, _, _, _): return [key]
        case let .macro(key, _, _, _): return [key]
        case let .turbo(key, _): return [key]
        case let .swipe(key, _, _): return [key]
        }
    }
}

public struct Keymap: Codable, Equatable {
    public static let maxElements = 200

    public var package: String?
    public var elements: [KeymapElement] = []
    public var gamepad: [String: UInt16]?

    public init(package: String? = nil, elements: [KeymapElement] = [], gamepad: [String: UInt16]? = nil) {
        self.package = package
        self.elements = elements
        self.gamepad = gamepad
    }

    public enum Problem: LocalizedError, Equatable {
        case tooManyElements
        case invalidPackage(String)
        case invalidPosition(label: String)
        case invalidJoystick(label: String)
        case invalidAim
        case invalidSkillShot(label: String)
        case invalidMacro(label: String)
        case invalidTurbo(label: String)
        case invalidSwipe(label: String)

        public var errorDescription: String? {
            switch self {
            case .tooManyElements: return "This keymap has too many buttons (the limit is \(Keymap.maxElements))."
            case let .invalidPackage(name): return "\"\(name)\" is not a valid app package name."
            case let .invalidPosition(label): return "A button\(label.isEmpty ? "" : " (\(label))") has an invalid position."
            case let .invalidMacro(label): return "A macro\(label.isEmpty ? "" : " (\(label))") is empty, too long, or has invalid steps."
            case let .invalidTurbo(label): return "A rapid-tap button\(label.isEmpty ? "" : " (\(label))") has an invalid rate."
            case let .invalidSwipe(label): return "A swipe\(label.isEmpty ? "" : " (\(label))") has an invalid end point or duration."
            case let .invalidSkillShot(label): return "A skill-shot\(label.isEmpty ? "" : " (\(label))") has invalid numbers."
            case .invalidAim: return "A keymap can have one free-look area, with a sensitivity and radius in range; mouse buttons must be 0 to 4."
            case let .invalidJoystick(label): return "A joystick\(label.isEmpty ? "" : " (\(label))") needs four different keys and valid numbers."
            }
        }
    }

    public func validated() throws -> Keymap {
        guard elements.count <= Self.maxElements else { throw Problem.tooManyElements }
        if let package, !ForegroundApp.isValidPackage(package) { throw Problem.invalidPackage(package) }

        var checked = self
        checked.gamepad = cleanedGamepad()
        for index in checked.elements.indices {
            guard checked.elements[index].position.isFinite else { throw Problem.invalidPosition(label: checked.elements[index].label) }
            checked.elements[index].position = checked.elements[index].position.clamped
            try Self.validateJoystick(&checked.elements[index])
            try Self.validateAim(&checked.elements[index])
            try Self.validateSkillShot(&checked.elements[index])
            try Self.validateMacro(&checked.elements[index])
            try Self.validateTurboAndSwipe(&checked.elements[index])
            checked.elements[index].label = ProfileFormat.cleanName(checked.elements[index].label, fallback: "")
        }
        guard checked.elements.filter({ if case .aim = $0.action { return true } else { return false } }).count <= 1 else {
            throw Problem.invalidAim
        }
        return checked
    }

    private static func validateMacro(_ element: inout KeymapElement) throws {
        guard case let .macro(key, steps, loop, speed) = element.action else { return }
        let invalid = Problem.invalidMacro(label: element.label)
        guard !steps.isEmpty, steps.count <= KeymapAction.maxMacroSteps, speed.isFinite else { throw invalid }

        var checked = steps
        for index in checked.indices {
            let step = checked[index]
            guard step.time.isFinite, (0...KeymapAction.maxMacroDuration).contains(step.time),
                  (0..<PointerID.slotCount).contains(step.finger), step.position.isFinite else { throw invalid }
            checked[index].position = step.position.clamped
        }
        checked = checked.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
        element.action = .macro(key: key, steps: checked, loop: loop,
                                speed: min(max(speed, KeymapAction.macroSpeedRange.lowerBound), KeymapAction.macroSpeedRange.upperBound))
    }

    private static func validateTurboAndSwipe(_ element: inout KeymapElement) throws {
        switch element.action {
        case let .turbo(key, rate):
            guard rate.isFinite else { throw Problem.invalidTurbo(label: element.label) }
            element.action = .turbo(key: key, rate: min(max(rate, KeymapAction.turboRateRange.lowerBound), KeymapAction.turboRateRange.upperBound))
        case let .swipe(key, to, duration):
            guard to.isFinite, duration.isFinite else { throw Problem.invalidSwipe(label: element.label) }
            element.action = .swipe(key: key, to: to.clamped,
                                    duration: min(max(duration, KeymapAction.swipeDurationRange.lowerBound), KeymapAction.swipeDurationRange.upperBound))
        default: break
        }
    }

    private static func validateSkillShot(_ element: inout KeymapElement) throws {
        guard case let .skillShot(key, cast, radius, range, hero) = element.action else { return }
        guard radius.isFinite, range.isFinite, hero.isFinite else { throw Problem.invalidSkillShot(label: element.label) }
        element.action = .skillShot(key: key, cast: cast,
                                    radius: min(max(radius, KeymapAction.radiusRange.lowerBound), KeymapAction.radiusRange.upperBound),
                                    range: min(max(range, KeymapAction.skillRange.lowerBound), KeymapAction.skillRange.upperBound),
                                    hero: hero.clamped)
    }

    private static func validateAim(_ element: inout KeymapElement) throws {
        switch element.action {
        case let .aim(toggleKey, sensitivity, radius):
            guard sensitivity.isFinite, radius.isFinite else { throw Problem.invalidAim }
            element.action = .aim(toggleKey: toggleKey,
                                  sensitivity: min(max(sensitivity, KeymapAction.sensitivityRange.lowerBound), KeymapAction.sensitivityRange.upperBound),
                                  radius: min(max(radius, KeymapAction.radiusRange.lowerBound), KeymapAction.radiusRange.upperBound))
        case let .mouseButton(button, _):
            guard KeymapAction.mouseButtons.contains(button) else { throw Problem.invalidAim }
        default:
            break
        }
    }

    private static func validateJoystick(_ element: inout KeymapElement) throws {
        guard case let .joystick(up, left, down, right, radius, response) = element.action else { return }
        guard Set([up, left, down, right]).count == 4, radius.isFinite, response.isFinite else {
            throw Problem.invalidJoystick(label: element.label)
        }
        element.action = .joystick(up: up, left: left, down: down, right: right,
                                   radius: min(max(radius, KeymapAction.radiusRange.lowerBound), KeymapAction.radiusRange.upperBound),
                                   response: min(max(response, KeymapAction.responseRange.lowerBound), KeymapAction.responseRange.upperBound))
    }
}
