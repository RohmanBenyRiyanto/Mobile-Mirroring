import Foundation

// MARK: State

/// The phone's developer switches that the Quick Toggles panel can change. Pure, so reading and writing are tested without a phone.
public struct DeveloperState: Equatable, Sendable, Codable {
    public enum NightMode: String, CaseIterable, Sendable, Codable { case auto, yes, no }

    public var layoutBounds = false
    public var gpuOverdraw = false
    public var dontKeepActivities = false
    public var animationScale = 1.0
    public var nightMode = NightMode.auto
    public var wifiOn = true
    public var mobileDataOn = true
    /// Interruptions silenced (the phone's Do Not Disturb, with priority exceptions), for playing without calls and banners.
    public var doNotDisturb = false

    public init() {}

    public static let animationScales: [Double] = [0, 0.5, 1, 1.5, 2, 5, 10]
}

public enum DeveloperSettings {
    public static let readCommand = "echo '##LAYOUT'; getprop debug.layout; echo '##OVERDRAW'; getprop debug.hwui.overdraw; "
        + "echo '##FINISH'; settings get global always_finish_activities; "
        + "echo '##ANIM'; settings get global window_animation_scale; settings get global transition_animation_scale; settings get global animator_duration_scale; "
        + "echo '##NIGHT'; cmd uimode night; echo '##WIFI'; settings get global wifi_on; echo '##DATA'; settings get global mobile_data; echo '##ZEN'; settings get global zen_mode"

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
        if let wifi = sections["WIFI"]?.first { state.wifiOn = wifi != "0" }
        if let data = sections["DATA"]?.first { state.mobileDataOn = data != "0" }
        if let zen = sections["ZEN"]?.first { state.doNotDisturb = zen != "0" && zen != "null" }
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
        if old.wifiOn != new.wifiOn { commands.append("svc wifi \(new.wifiOn ? "enable" : "disable")") }
        if old.doNotDisturb != new.doNotDisturb { commands.append("cmd notification set_dnd \(new.doNotDisturb ? "priority" : "off")") }
        if old.mobileDataOn != new.mobileDataOn { commands.append("svc data \(new.mobileDataOn ? "enable" : "disable")") }
        return commands
    }
}


/// Things the app changes on a phone and must never leave behind, even if it was killed before it could put them back.
public enum LeftoverSettings {
    /// A proxy that points at this Mac's loopback (the API log's) can only be ours. With nothing listening, every app that honours the
    /// system proxy (browsers, TikTok…) loses its internet while games and chat apps still work, so a new session removes it.
    public static let clearLoopbackProxyCommand =
        "p=$(settings get global http_proxy); case \"$p\" in 127.0.0.1:*) settings put global http_proxy :0; settings delete global http_proxy; echo cleared;; esac"

    public static func didClear(_ output: String) -> Bool { output.contains("cleared") }
}
