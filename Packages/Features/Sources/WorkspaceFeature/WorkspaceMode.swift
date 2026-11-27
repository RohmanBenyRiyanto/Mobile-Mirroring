import SwiftUI

/// What the phone window is being used for. It decides which tools the control rail offers, so the ones needed now are one
/// click away: Normal is everyday use, Gaming is for playing with a keymap and streaming, Developer is for inspecting an app.
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

    /// The digit of the shortcut (⌥⌘1, ⌥⌘2, ⌥⌘3).
    public var shortcutKey: Character {
        switch self {
        case .normal: return "1"
        case .gaming: return "2"
        case .developer: return "3"
        }
    }
}

/// When the window goes to Gaming mode by itself (only if the user turned that on), and when it goes back.
/// A mode the user picked by hand is never taken away.
public struct ModeAutoSwitch: Equatable {
    public var mode: WorkspaceMode
    /// The mode to return to when the game closes, set only while Gaming was entered automatically.
    public var restoreTo: WorkspaceMode?

    public init(mode: WorkspaceMode, restoreTo: WorkspaceMode? = nil) {
        self.mode = mode
        self.restoreTo = restoreTo
    }

    /// A game with a keymap came to the front and the keymap was switched on automatically.
    public func keymapTurnedOnAutomatically(enabled: Bool) -> ModeAutoSwitch {
        guard enabled, mode != .gaming else { return self }
        return ModeAutoSwitch(mode: .gaming, restoreTo: mode)
    }

    /// The game closed and the keymap was switched off automatically.
    public func keymapTurnedOffAutomatically() -> ModeAutoSwitch {
        guard let restoreTo, mode == .gaming else { return self }
        return ModeAutoSwitch(mode: restoreTo, restoreTo: nil)
    }

    /// The user chose a mode: from now on it is theirs, nothing returns it anywhere.
    public func chosen(_ newMode: WorkspaceMode) -> ModeAutoSwitch { ModeAutoSwitch(mode: newMode, restoreTo: nil) }
}
