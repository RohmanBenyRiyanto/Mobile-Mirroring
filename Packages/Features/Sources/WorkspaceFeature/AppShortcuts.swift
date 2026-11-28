import AppKit
import SwiftUI

public struct KeyCombo: Hashable, Codable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    public let key: String
    public let modifiers: Modifiers

    public init(_ key: String, _ modifiers: Modifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }

    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }

    var keyEquivalent: KeyEquivalent? {
        switch key {
        case "↩": return .return
        case "↑": return .upArrow
        case "↓": return .downArrow
        case "←": return .leftArrow
        case "→": return .rightArrow
        case "⇥": return .tab
        case "Space": return .space
        case "⌫": return .delete
        default: return key.count == 1 ? KeyEquivalent(Character(key.lowercased())) : nil
        }
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.command) { result.insert(.command) }
        return result
    }

    public init?(event: NSEvent) {
        var modifiers: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let named: [UInt16: String] = [36: "↩", 76: "↩", 126: "↑", 125: "↓", 123: "←", 124: "→", 48: "⇥", 49: "Space", 51: "⌫"]
        if let name = named[event.keyCode] {
            self.init(name, modifiers)
        } else if let characters = event.charactersIgnoringModifiers?.uppercased(), characters.count == 1, characters.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace }) {
            self.init(characters, modifiers)
        } else {
            return nil
        }
    }
}

public enum ShortcutRegistry {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: String
        public let menu: String
        public let title: String
        public let original: KeyCombo
    }

    public static let items: [Item] = rows.map { Item(id: $0.0, menu: $0.1, title: $0.2, original: $0.3) }

    public static func item(_ id: String) -> Item? { items.first { $0.id == id } }

    private static let rows: [(String, String, String, KeyCombo)] = [
        ("File.New Tab", "File", "New Tab", KeyCombo("T", [.command])),
        ("File.Install APK", "File", "Install APK", KeyCombo("O", [.command])),
        ("File.Send File", "File", "Send File", KeyCombo("O", [.command, .shift])),
        ("File.Close Tab", "File", "Close Tab", KeyCombo("W", [.command])),
        ("Edit.Send Clipboard Image to Phone", "Edit", "Send Clipboard Image to Phone", KeyCombo("V", [.command, .option])),
        ("View.Statistics", "View", "Statistics", KeyCombo("I", [.command])),
        ("View.Developer HUD", "View", "Developer HUD", KeyCombo("I", [.command, .shift])),
        ("View.Control Rail", "View", "Control Rail", KeyCombo("R", [.command, .option])),
        ("View.Stream Mode", "View", "Stream Mode", KeyCombo("B", [.command, .shift])),
        ("Mirror.Start Mirroring", "Mirror", "Start Mirroring", KeyCombo("↩", [.command])),
        ("Mirror.Disconnect", "Mirror", "Disconnect", KeyCombo("D", [.command, .shift])),
        ("Mirror.Screenshot", "Mirror", "Screenshot", KeyCombo("S", [.command])),
        ("Mirror.Start Recording", "Mirror", "Start Recording", KeyCombo("R", [.command, .shift])),
        ("Mirror.Mute Audio", "Mirror", "Mute Audio", KeyCombo("M", [.command, .shift])),
        ("Mirror.Mini Mirror", "Mirror", "Mini Mirror", KeyCombo("Y", [.command, .shift])),
        ("Mirror.Keep on Top", "Mirror", "Keep on Top", KeyCombo("Y", [.command, .option])),
        ("Mirror.Copy OBS URL", "Mirror", "Copy OBS URL", KeyCombo("C", [.command, .shift])),
        ("Mirror.Actual Pixel Size", "Mirror", "Actual Pixel Size", KeyCombo("1", [.command])),
        ("Device.Back", "Device", "Back", KeyCombo("[", [.command])),
        ("Device.Home", "Device", "Home", KeyCombo("H", [.command, .shift])),
        ("Device.Recents", "Device", "Recents", KeyCombo("A", [.command, .shift])),
        ("Device.Volume Up", "Device", "Volume Up", KeyCombo("↑", [.command])),
        ("Device.Volume Down", "Device", "Volume Down", KeyCombo("↓", [.command])),
        ("Device.Power", "Device", "Power", KeyCombo("P", [.command, .shift])),
        ("Device.Notifications", "Device", "Notifications", KeyCombo("N", [.command, .shift])),
        ("Device.Quick Settings", "Device", "Quick Settings", KeyCombo("N", [.command, .option])),
        ("Device.Rotate", "Device", "Rotate", KeyCombo("R", [.command])),
        ("Device.Switch to Wi-Fi", "Device", "Switch to Wi-Fi", KeyCombo("E", [.command, .shift])),
        ("Device.UI Inspector", "Device", "UI Inspector", KeyCombo("I", [.command, .option])),
        ("Device.Design Overlay", "Device", "Design Overlay", KeyCombo("G", [.command, .option])),
        ("Device.Logcat", "Device", "Logcat", KeyCombo("L", [.command, .shift])),
        ("Device.API Log", "Device", "API Log", KeyCombo("A", [.command, .option])),
        ("Device.Database", "Device", "Database", KeyCombo("D", [.command, .option])),
        ("Device.Inspector Panel", "Device", "Inspector Panel", KeyCombo("P", [.command, .option])),
        ("Device.Quick Toggles", "Device", "Quick Toggles", KeyCombo("J", [.command, .option])),
        ("Keymap.Edit Keymap", "Keymap", "Edit Keymap", KeyCombo("E", [.command])),
        ("Keymap.Add Tap", "Keymap", "Add Tap", KeyCombo("1", [])),
        ("Keymap.Add Hold", "Keymap", "Add Hold", KeyCombo("2", [])),
        ("Keymap.Add Toggle", "Keymap", "Add Toggle", KeyCombo("3", [])),
        ("Keymap.Add Joystick", "Keymap", "Add Joystick", KeyCombo("4", [])),
        ("Keymap.Add Aim", "Keymap", "Add Aim", KeyCombo("5", [])),
        ("Keymap.Add Skill Shot", "Keymap", "Add Skill Shot", KeyCombo("6", [])),
        ("Keymap.Add Rapid Tap", "Keymap", "Add Rapid Tap", KeyCombo("8", [])),
        ("Keymap.Add Swipe", "Keymap", "Add Swipe", KeyCombo("9", [])),
        ("Keymap.Record Macro", "Keymap", "Record Macro", KeyCombo("7", [])),
        ("Keymap.Keymap Enabled", "Keymap", "Keymap Enabled", KeyCombo("K", [.command, .shift])),
        ("Logcat.Pause", "Logcat", "Pause", KeyCombo("Space", [])),
        ("Logcat.Clear", "Logcat", "Clear", KeyCombo("K", [.command])),
        ("Logcat.Filter", "Logcat", "Filter", KeyCombo("F", [.command, .option])),
        ("Window.Show Previous Phone", "Window", "Show Previous Phone", KeyCombo("⇥", [.control, .shift])),
        ("Window.Show Next Phone", "Window", "Show Next Phone", KeyCombo("⇥", [.control])),
    ]

    public static let reserved: Set<KeyCombo> = [
        KeyCombo("Q"), KeyCombo("H"), KeyCombo("M"), KeyCombo(","), KeyCombo("Z"), KeyCombo("Z", [.command, .shift]),
        KeyCombo("X"), KeyCombo("C"), KeyCombo("V"), KeyCombo("A"), KeyCombo("H", [.command, .option]), KeyCombo("M", [.command, .option]),
    ]
}

public struct ShortcutBook: Equatable, Codable, Sendable {
    public var overrides: [String: KeyCombo?] = [:]

    public init() {}

    public func combo(for id: String) -> KeyCombo? {
        if let changed = overrides[id] { return changed }
        return ShortcutRegistry.item(id)?.original
    }

    public func isChanged(_ id: String) -> Bool { overrides[id] != nil }

    public func conflict(for combo: KeyCombo?, excluding id: String) -> ShortcutRegistry.Item? {
        guard let combo else { return nil }
        return ShortcutRegistry.items.first { $0.id != id && self.combo(for: $0.id) == combo }
    }

    public mutating func set(_ combo: KeyCombo?, for id: String) {
        if combo == ShortcutRegistry.item(id)?.original { overrides[id] = nil } else { overrides[id] = .some(combo) }
    }

    public mutating func reset(_ id: String) { overrides[id] = nil }

    public static let defaultsKey = "shortcuts.v1"

    public static func load(from defaults: UserDefaults) -> ShortcutBook {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(ShortcutBook.self, from: $0) } ?? ShortcutBook()
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

extension View {
    @ViewBuilder
    func appShortcut(_ id: String, model: AppModel) -> some View {
        if let combo = model.shortcuts.combo(for: id), let key = combo.keyEquivalent {
            keyboardShortcut(key, modifiers: combo.eventModifiers)
        } else {
            self
        }
    }
}
