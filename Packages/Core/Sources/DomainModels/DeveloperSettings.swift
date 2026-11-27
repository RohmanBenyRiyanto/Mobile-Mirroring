import Foundation

// MARK: State

/// The phone's developer switches that the Quick Toggles panel can change. Pure, so reading and writing are tested without a phone.
public struct DeveloperState: Equatable, Sendable {
    public enum NightMode: String, CaseIterable, Sendable { case auto, yes, no }

    public var layoutBounds = false
    public var gpuOverdraw = false
    public var dontKeepActivities = false
    public var animationScale = 1.0
    public var nightMode = NightMode.auto

    public init() {}

    public static let animationScales: [Double] = [0, 0.5, 1, 1.5, 2, 5, 10]
}

public enum DeveloperSettings {
    public static let readCommand = "echo '##LAYOUT'; getprop debug.layout; echo '##OVERDRAW'; getprop debug.hwui.overdraw; "
        + "echo '##FINISH'; settings get global always_finish_activities; "
        + "echo '##ANIM'; settings get global window_animation_scale; settings get global transition_animation_scale; settings get global animator_duration_scale; "
        + "echo '##NIGHT'; cmd uimode night"

    public static func parse(_ output: String) -> DeveloperState {
        var sections: [String: [String]] = [:]
        var current = ""
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("##") { current = String(text.dropFirst(2)); continue }
            if !text.isEmpty { sections[current, default: []].append(text) }
        }
        var state = DeveloperState()
        state.layoutBounds = sections["LAYOUT"]?.first == "true"
        state.gpuOverdraw = sections["OVERDRAW"]?.first == "show"
        state.dontKeepActivities = sections["FINISH"]?.first == "1"
        // The three scales are normally equal; the window scale stands for all of them.
        if let first = sections["ANIM"]?.first, let value = Double(first) { state.animationScale = value }
        if let night = sections["NIGHT"]?.first?.lowercased() {
            if night.hasSuffix("yes") { state.nightMode = .yes } else if night.hasSuffix("no") { state.nightMode = .no }
        }
        return state
    }

    /// Shell commands that move the phone from `old` to `new`, touching only what differs. Every value is built here, never taken from outside.
    public static func commands(from old: DeveloperState, to new: DeveloperState) -> [String] {
        var commands: [String] = []
        if old.layoutBounds != new.layoutBounds { commands.append("setprop debug.layout \(new.layoutBounds ? "true" : "''")") }
        if old.gpuOverdraw != new.gpuOverdraw { commands.append("setprop debug.hwui.overdraw \(new.gpuOverdraw ? "show" : "''")") }
        if old.dontKeepActivities != new.dontKeepActivities { commands.append("settings put global always_finish_activities \(new.dontKeepActivities ? 1 : 0)") }
        if old.animationScale != new.animationScale {
            let value = String(format: "%g", new.animationScale)
            for key in ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"] {
                commands.append("settings put global \(key) \(value)")
            }
        }
        if old.nightMode != new.nightMode { commands.append("cmd uimode night \(new.nightMode.rawValue)") }
        return commands
    }
}
