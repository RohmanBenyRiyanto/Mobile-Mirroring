import Foundation
import WorkspaceFeature

public struct ShortcutCatalog {
    public struct Entry: Identifiable, Equatable {
        public let id: String
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

    public init(entries: [Entry]) { self.entries = entries }

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

    public func conflict(of entry: Entry) -> Entry? {
        entries.first { $0.id != entry.id && $0.combo == entry.combo }
    }
}
