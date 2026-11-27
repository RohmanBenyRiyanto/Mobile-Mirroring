import Foundation

/// One keyboard shortcut: a key and its modifiers, written the way macOS shows them (⇧⌘H).
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

    /// "⇧⌘H": control, option, shift, command, then the key (the order macOS uses).
    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }
}

/// Every shortcut of the menu bar, for Settings › Shortcuts. The menu itself is the source of the shortcuts; this list mirrors it
/// (a test checks that no two entries share a combination).
public struct ShortcutCatalog {
    public struct Entry: Identifiable, Equatable {
        public let id: String
        /// The name of the menu item, as the string catalog knows it.
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
            e("Device", "Switch to Wi-Fi…", "E", shift), e("Device", "UI Inspector", "I", option), e("Device", "Design Overlay", "G", option),
            e("Device", "Logcat", "L", shift), e("Device", "Quick Toggles", "J", option),
            e("View", "Statistics", "I", cmd), e("View", "Developer HUD", "I", shift), e("View", "Control Rail", "R", option),
            e("View", "Stream Mode", "B", shift),
            e("File", "New Tab", "T", cmd), e("File", "Install APK…", "O", cmd), e("File", "Send File…", "O", shift), e("File", "Close Tab", "W", cmd),
            e("Edit", "Paste to Phone", "V", cmd), e("Edit", "Copy from Phone", "C", cmd),
            e("Keymap", "Edit Keymap", "E", cmd), e("Keymap", "Add Tap", "1", []), e("Keymap", "Add Hold", "2", []), e("Keymap", "Add Toggle", "3", []),
            e("Keymap", "Add Joystick", "4", []), e("Keymap", "Add Aim", "5", []), e("Keymap", "Add Skill Shot", "6", []),
            e("Keymap", "Record Macro", "7", []), e("Keymap", "Keymap Enabled", "K", shift),
            e("Logcat", "Pause", "Space", []), e("Logcat", "Clear", "K", cmd), e("Logcat", "Filter…", "F", option),
        ]
    }

    /// Entries whose name or shortcut contains the text, ignoring case. An empty text keeps everything.
    public func filtered(by query: String) -> [Entry] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return entries }
        return entries.filter { $0.title.lowercased().contains(text) || $0.combo.display.lowercased().contains(text) || $0.menu.lowercased().contains(text) }
    }

    /// Entries that share a combination with another one, grouped by that combination.
    public func conflicts() -> [KeyCombo: [Entry]] {
        Dictionary(grouping: entries, by: \.combo).filter { $0.value.count > 1 }
    }

    /// "⌘I is also assigned to Install APK." for the entry, or nil when its shortcut is its own.
    public func conflict(of entry: Entry) -> Entry? {
        entries.first { $0.id != entry.id && $0.combo == entry.combo }
    }
}
