import Foundation
import Persistence

/// The rules for switching keymaps by themselves when the game in front on the phone changes.
/// Pure functions, so every case can be tested without a phone.
public enum KeymapAutoSwitch {
    public enum Action: Equatable {
        case load(String)
        case enable
        case disable
    }

    /// What to do when `package` has just come to the front.
    ///
    /// - A game with a keymap: load it if it is not loaded, and (if allowed) switch it on.
    /// - Any other app: switch the keymap off again, but only if the app switched it on. A keymap the user switched on
    ///   by hand is never taken away.
    public static func actions(foreground package: String?, index: [String: String], loadedProfileID: String?,
                        isEnabled: Bool, wasAutoEnabled: Bool, enablesAutomatically: Bool) -> [Action] {
        guard let package else { return [] } // nothing known yet (a transition): keep things as they are

        if let id = index[package] {
            var actions: [Action] = []
            if loadedProfileID != id { actions.append(.load(id)) }
            if enablesAutomatically, !isEnabled { actions.append(.enable) }
            return actions
        }
        return wasAutoEnabled && isEnabled ? [.disable] : []
    }

    /// Which saved keymap belongs to which game: package name → profile id. If two keymaps name the same game,
    /// the one saved most recently wins. Keymaps without a valid package are left out.
    public static func index(from profiles: [Profile<Keymap>]) -> [String: String] {
        var newest: [String: Profile<Keymap>] = [:]
        for profile in profiles {
            guard let package = profile.payload.package, ForegroundApp.isValidPackage(package) else { continue }
            if let existing = newest[package], existing.modified >= profile.modified { continue }
            newest[package] = profile
        }
        return newest.mapValues(\.id)
    }
}
