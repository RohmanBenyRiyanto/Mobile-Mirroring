import Foundation
import WorkspaceFeature

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

    /// The original shortcuts, from the same list the menu uses.
    public init() {
        entries = ShortcutRegistry.items.map { Entry(id: $0.id, title: $0.title, menu: $0.menu, combo: $0.original) }
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
