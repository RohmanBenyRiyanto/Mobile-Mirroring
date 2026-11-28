import Foundation
import Persistence

public enum KeymapAutoSwitch {
    public enum Action: Equatable {
        case load(String)
        case enable
        case disable
    }

    public static func actions(foreground package: String?, index: [String: String], loadedProfileID: String?,
                        isEnabled: Bool, wasAutoEnabled: Bool, enablesAutomatically: Bool) -> [Action] {
        guard let package else { return [] }

        if let id = index[package] {
            var actions: [Action] = []
            if loadedProfileID != id { actions.append(.load(id)) }
            if enablesAutomatically, !isEnabled { actions.append(.enable) }
            return actions
        }
        return wasAutoEnabled && isEnabled ? [.disable] : []
    }

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
