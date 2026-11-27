import Foundation
import Persistence

/// What an imported keymap contains, in words, so the user can decide before it is saved. A keymap from somebody
/// else is not trusted: it can replay recorded touches and switch itself on for a game.
public struct KeymapSummary: Equatable {
    public let name: String
    public let package: String?
    /// How many of each kind of element, in a fixed order, kinds with none left out.
    public let counts: [(kind: String, count: Int)]
    public let macroCount: Int
    public let macroSteps: Int
    public let macroSeconds: Double
    public let usesFreeLook: Bool
    /// The id the keymap will be saved under if it differs from its own (the name was taken).
    public let savedAs: String?

    public init(profile: Profile<Keymap>, existingIDs: Set<String>) {
        let elements = profile.payload.elements
        name = profile.name
        package = profile.payload.package

        var buttons = 0, joysticks = 0, aims = 0, mouse = 0, skills = 0, macros = 0, steps = 0
        var seconds = 0.0
        for element in elements {
            switch element.action {
            case .button: buttons += 1
            case .joystick: joysticks += 1
            case .aim: aims += 1
            case .mouseButton: mouse += 1
            case .skillShot: skills += 1
            case let .macro(_, macroSteps, _, _):
                macros += 1
                steps += macroSteps.count
                seconds += macroSteps.last?.time ?? 0
            }
        }
        counts = [("Buttons", buttons), ("Joysticks", joysticks), ("Free-look", aims), ("Mouse buttons", mouse), ("Skill-shots", skills), ("Macros", macros)]
            .filter { $0.1 > 0 }
            .map { (kind: $0.0, count: $0.1) }
        macroCount = macros
        macroSteps = steps
        macroSeconds = seconds
        usesFreeLook = aims > 0

        if existingIDs.contains(profile.id) {
            var number = 2
            while existingIDs.contains("\(profile.id)-\(number)") { number += 1 }
            savedAs = "\(profile.id)-\(number)"
        } else {
            savedAs = nil
        }
    }

    public static func == (lhs: KeymapSummary, rhs: KeymapSummary) -> Bool {
        lhs.name == rhs.name && lhs.package == rhs.package && lhs.counts.map(\.kind) == rhs.counts.map(\.kind)
            && lhs.counts.map(\.count) == rhs.counts.map(\.count) && lhs.macroSteps == rhs.macroSteps && lhs.savedAs == rhs.savedAs
    }

    public var warnings: [String] {
        var list: [String] = []
        if macroCount > 0 {
            list.append("\(macroCount) macro\(macroCount == 1 ? "" : "s") (\(macroSteps) recorded touches, \(String(format: "%.1f", macroSeconds)) s) will replay on your phone when you press their key.")
        }
        if let package {
            list.append("It switches on by itself whenever \(package) is open on the phone, and then takes over its keys.")
        }
        if usesFreeLook {
            list.append("Free-look captures and hides your mouse pointer while it is on.")
        }
        if let savedAs {
            list.append("You already have a keymap with this name; this one is saved as \"\(savedAs)\" and nothing is replaced.")
        }
        return list
    }

    public var message: String {
        let contents = counts.isEmpty ? "No elements." : counts.map { "\($0.count) \($0.kind.lowercased())" }.joined(separator: ", ") + "."
        return ([contents] + warnings.map { "• " + $0 }).joined(separator: "\n\n")
    }
}
