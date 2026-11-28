import Foundation

public enum DeviceTool: CaseIterable, Identifiable {
    case darkModeOn, darkModeOff, darkModeAuto
    case animationsOff, animationsOn
    case pointerLocationOn, pointerLocationOff

    public var id: Self { self }

    public var title: String {
        switch self {
        case .darkModeOn: return "Dark Mode: On"
        case .darkModeOff: return "Dark Mode: Off"
        case .darkModeAuto: return "Dark Mode: Automatic"
        case .animationsOff: return "Animations: Off"
        case .animationsOn: return "Animations: Normal"
        case .pointerLocationOn: return "Pointer Location: On"
        case .pointerLocationOff: return "Pointer Location: Off"
        }
    }

    public var shellCommands: [[String]] {
        switch self {
        case .darkModeOn: return [["cmd", "uimode", "night", "yes"]]
        case .darkModeOff: return [["cmd", "uimode", "night", "no"]]
        case .darkModeAuto: return [["cmd", "uimode", "night", "auto"]]
        case .animationsOff: return Self.animationScales(0)
        case .animationsOn: return Self.animationScales(1)
        case .pointerLocationOn: return [["settings", "put", "system", "pointer_location", "1"]]
        case .pointerLocationOff: return [["settings", "put", "system", "pointer_location", "0"]]
        }
    }

    private static func animationScales(_ scale: Int) -> [[String]] {
        ["window_animation_scale", "transition_animation_scale", "animator_duration_scale"]
            .map { ["settings", "put", "global", $0, String(scale)] }
    }
}
