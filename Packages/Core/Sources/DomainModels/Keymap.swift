import CoreGraphics
import Foundation
import Persistence

/// A point on the phone's screen as a fraction (0…1) of its width and height, so a keymap keeps working
/// on a phone with a different resolution.
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

/// What a button does to the touch while its key is used.
public enum ButtonMode: String, Codable, CaseIterable, Identifiable {
    /// A quick touch each time the key is pressed.
    case tap
    /// The finger stays down for as long as the key is held (a fire button).
    case hold
    /// One press puts the finger down, the next lifts it (hold-to-aim, auto-fire).
    case toggle

    public var id: String { rawValue }
}

/// One touch event of a recorded macro. `time` is seconds from the start of the macro; `finger` numbers the
/// simultaneous fingers (0, 1, …) within the macro, independent of the phone's pointer ids.
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

/// When an aimed skill is cast.
public enum SkillCast: String, Codable, CaseIterable, Identifiable {
    /// Hold the key to aim with the mouse, release to cast.
    case onRelease
    /// Cast at once towards the mouse when the key is pressed (quick cast).
    case instant

    public var id: String { rawValue }
}

public enum KeymapAction: Codable, Equatable {
    case button(key: UInt16, mode: ButtonMode)
    /// Four keys that steer a virtual analog stick centred on the element's position.
    /// `radius` is a fraction of the screen's shorter edge; `response` is how many seconds the stick takes to
    /// reach full deflection (0 = instantly), which gives movement a smooth start and stop.
    case joystick(up: UInt16, left: UInt16, down: UInt16, right: UInt16, radius: Double, response: Double)

    /// Free-look: while switched on with `toggleKey`, the mouse is captured and its movement drags a finger around
    /// the element's position (the camera). `sensitivity` is screen pixels per mouse point on a 1080-wide screen;
    /// `radius` (fraction of the shorter edge) is how far the finger roams before it is put back in the middle.
    case aim(toggleKey: UInt16, sensitivity: Double, radius: Double)
    /// A mouse button (0 left, 1 right, 2 and up the others) that touches the element's position. Active only while aiming.
    case mouseButton(button: Int, mode: ButtonMode)

    /// An aimed skill (MOBA). The element's position is the skill button. While the key is held the finger is
    /// dragged from the button in the direction of the mouse as seen from the hero's position `hero`; the drag
    /// reaches `radius` (fraction of the shorter edge) when the mouse is `range` (same unit) or more from the hero.
    case skillShot(key: UInt16, cast: SkillCast, radius: Double, range: Double, hero: NormalizedPoint)

    /// A recorded sequence of touches, played when the key is pressed. With `loop` it repeats for as long as the
    /// key is held and stops (lifting its fingers) on release. `speed` scales the playback time.
    case macro(key: UInt16, steps: [MacroStep], loop: Bool, speed: Double)

    public static let maxMacroSteps = 5_000
    public static let maxMacroDuration = 120.0
    public static let macroSpeedRange = 0.1...5.0

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

    /// The keys this element listens to.
    public var keys: [UInt16] {
        switch action {
        case let .button(key, _): return [key]
        case let .joystick(up, left, down, right, _, _): return [up, left, down, right]
        case let .aim(toggleKey, _, _): return [toggleKey]
        case .mouseButton: return []
        case let .skillShot(key, _, _, _, _): return [key]
        case let .macro(key, _, _, _): return [key]
        }
    }
}

/// Keyboard controls for one game: where each key touches the screen.
public struct Keymap: Codable, Equatable {
    public static let maxElements = 200

    /// The game this keymap belongs to, if any (used to switch keymaps automatically).
    public var package: String?
    public var elements: [KeymapElement] = []

    public init(package: String? = nil, elements: [KeymapElement] = []) {
        self.package = package
        self.elements = elements
    }

    public enum Problem: LocalizedError, Equatable {
        case tooManyElements
        case invalidPackage(String)
        case invalidPosition(label: String)
        case invalidJoystick(label: String)
        case invalidAim
        case invalidSkillShot(label: String)
        case invalidMacro(label: String)

        public var errorDescription: String? {
            switch self {
            case .tooManyElements: return "This keymap has too many buttons (the limit is \(Keymap.maxElements))."
            case let .invalidPackage(name): return "\"\(name)\" is not a valid app package name."
            case let .invalidPosition(label): return "A button\(label.isEmpty ? "" : " (\(label))") has an invalid position."
            case let .invalidMacro(label): return "A macro\(label.isEmpty ? "" : " (\(label))") is empty, too long, or has invalid steps."
            case let .invalidSkillShot(label): return "A skill-shot\(label.isEmpty ? "" : " (\(label))") has invalid numbers."
            case .invalidAim: return "A keymap can have one free-look area, with a sensitivity and radius in range; mouse buttons must be 0 to 4."
            case let .invalidJoystick(label): return "A joystick\(label.isEmpty ? "" : " (\(label))") needs four different keys and valid numbers."
            }
        }
    }

    /// Checks a keymap that came from a file and clamps stray positions into the screen.
    public func validated() throws -> Keymap {
        guard elements.count <= Self.maxElements else { throw Problem.tooManyElements }
        if let package, !ForegroundApp.isValidPackage(package) { throw Problem.invalidPackage(package) }

        var checked = self
        for index in checked.elements.indices {
            guard checked.elements[index].position.isFinite else { throw Problem.invalidPosition(label: checked.elements[index].label) }
            checked.elements[index].position = checked.elements[index].position.clamped
            try Self.validateJoystick(&checked.elements[index])
            try Self.validateAim(&checked.elements[index])
            try Self.validateSkillShot(&checked.elements[index])
            try Self.validateMacro(&checked.elements[index])
            checked.elements[index].label = ProfileFormat.cleanName(checked.elements[index].label, fallback: "")
        }
        guard checked.elements.filter({ if case .aim = $0.action { return true } else { return false } }).count <= 1 else {
            throw Problem.invalidAim
        }
        return checked
    }

    /// A macro must have steps that fit the limits; they are sorted by time and their positions pulled into the screen.
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

    /// A joystick must use four different keys and finite numbers; the numbers are pulled into their ranges.
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
