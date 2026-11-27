import SwiftUI

/// The phone window's purpose, which decides the control rail tools offered.
public enum WorkspaceMode: String, CaseIterable, Identifiable, Codable {
    case normal, gaming, developer

    public var id: String { rawValue }

    public var title: LocalizedStringKey {
        switch self {
        case .normal: return "Normal"
        case .gaming: return "Gaming"
        case .developer: return "Developer"
        }
    }

    public var symbol: String {
        switch self {
        case .normal: return "iphone"
        case .gaming: return "gamecontroller"
        case .developer: return "wrench.and.screwdriver"
        }
    }

    public var shortcutKey: Character {
        switch self {
        case .normal: return "1"
        case .gaming: return "2"
        case .developer: return "3"
        }
    }
}

/// Switches to Gaming mode by itself when a keymap turns on, and back when it turns off. A chosen mode is never changed.
public struct ModeAutoSwitch: Equatable {
    public var mode: WorkspaceMode
    /// The mode to return to when the game closes, set only while Gaming was entered automatically.
    public var restoreTo: WorkspaceMode?

    public init(mode: WorkspaceMode, restoreTo: WorkspaceMode? = nil) {
        self.mode = mode
        self.restoreTo = restoreTo
    }

    public func keymapTurnedOnAutomatically(enabled: Bool) -> ModeAutoSwitch {
        guard enabled, mode != .gaming else { return self }
        return ModeAutoSwitch(mode: .gaming, restoreTo: mode)
    }

    public func keymapTurnedOffAutomatically() -> ModeAutoSwitch {
        guard let restoreTo, mode == .gaming else { return self }
        return ModeAutoSwitch(mode: restoreTo, restoreTo: nil)
    }

    /// The user chose a mode: from now on it is theirs, nothing returns it anywhere.
    public func chosen(_ newMode: WorkspaceMode) -> ModeAutoSwitch { ModeAutoSwitch(mode: newMode, restoreTo: nil) }
}
