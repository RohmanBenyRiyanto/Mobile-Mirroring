import Foundation

public struct KeyCombo: Hashable {
    public struct Modifiers: OptionSet, Hashable {
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

    /// Formats the shortcut in macOS order: control, option, shift, command, then the key.
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }
}

/// Mirrors the menu bar shortcuts. A test checks that no two entries share a combination.
public struct ShortcutCatalog {
    public struct Entry: Identifiable, Equatable {
        public let id: String
        /// Must match the menu item's localized name.
        public let title: String
        public let menu: String
        public let combo: KeyCombo

        public init(id: String, title: String, menu: String, combo: KeyCombo) {
            self.id = id
            self.title = title
            self.menu = menu
            self.combo = combo
        }
    }

    public static let shared = ShortcutCatalog()

    public let entries: [Entry]

    /// An explicit list, for tests.
    public init(entries: [Entry]) { self.entries = entries }

    public init() {
        func e(_ menu: String, _ title: String, _ key: String, _ modifiers: KeyCombo.Modifiers = .command) -> Entry {
            Entry(id: "\(menu).\(title)", title: title, menu: menu, combo: KeyCombo(key, modifiers))
        }
        let (cmd, shift, option): (KeyCombo.Modifiers, KeyCombo.Modifiers, KeyCombo.Modifiers) = (.command, [.command, .shift], [.command, .option])
        entries = [
            e("Mirror", "Normal", "1", option), e("Mirror", "Gaming", "2", option), e("Mirror", "Developer", "3", option),
            e("Mirror", "Start Mirroring", "↩", cmd), e("Mirror", "Disconnect", "D", shift), e("Mirror", "Screenshot", "S", cmd),
            e("Mirror", "Start Recording", "R", shift), e("Mirror", "Mute Audio", "M", shift), e("Mirror", "Mini Mirror", "Y", shift),
            e("Mirror", "Keep on Top", "Y", option), e("Mirror", "Copy OBS URL", "C", shift), e("Mirror", "Actual Pixel Size", "1", cmd),
            e("Device", "Back", "[", cmd), e("Device", "Home", "H", shift), e("Device", "Recents", "A", shift),
            e("Device", "Volume Up", "↑", cmd), e("Device", "Volume Down", "↓", cmd), e("Device", "Power", "P", shift),
            e("Device", "Notifications", "N", shift), e("Device", "Quick Settings", "N", option), e("Device", "Rotate", "R", cmd),
            e("Device", "Switch to Wi-Fi", "E", shift), e("Device", "UI Inspector", "I", option), e("Device", "Design Overlay", "G", option),
            e("Device", "Logcat", "L", shift), e("Device", "Quick Toggles", "J", option),
            e("View", "Statistics", "I", cmd), e("View", "Developer HUD", "I", shift), e("View", "Control Rail", "R", option),
            e("View", "Stream Mode", "B", shift),
            e("File", "New Tab", "T", cmd), e("File", "Install APK", "O", cmd), e("File", "Send File", "O", shift), e("File", "Close Tab", "W", cmd),
            e("Edit", "Paste to Phone", "V", cmd), e("Edit", "Copy from Phone", "C", cmd),
            e("Keymap", "Edit Keymap", "E", cmd), e("Keymap", "Add Tap", "1", []), e("Keymap", "Add Hold", "2", []), e("Keymap", "Add Toggle", "3", []),
            e("Keymap", "Add Joystick", "4", []), e("Keymap", "Add Aim", "5", []), e("Keymap", "Add Skill Shot", "6", []),
            e("Keymap", "Record Macro", "7", []), e("Keymap", "Keymap Enabled", "K", shift),
            e("Logcat", "Pause", "Space", []), e("Logcat", "Clear", "K", cmd), e("Logcat", "Filter", "F", option),
        ]
    }

    public func filtered(by query: String) -> [Entry] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return entries }
        return entries.filter { $0.title.lowercased().contains(text) || $0.combo.display.lowercased().contains(text) || $0.menu.lowercased().contains(text) }
    }

    public func conflicts() -> [KeyCombo: [Entry]] {
        Dictionary(grouping: entries, by: \.combo).filter { $0.value.count > 1 }
    }

    /// The other entry that uses this entry's combination, or nil.
    public func conflict(of entry: Entry) -> Entry? {
        entries.first { $0.id != entry.id && $0.combo == entry.combo }
    }
}
