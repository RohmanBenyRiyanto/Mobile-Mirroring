import SwiftUI
import Theme

public struct PickerItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let badge: LocalizedStringKey?

    public init(id: String, title: String, subtitle: String? = nil, badge: LocalizedStringKey? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
    }

    public static func == (lhs: PickerItem, rhs: PickerItem) -> Bool { lhs.id == rhs.id && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle }
}

/// A button that shows the current choice and opens a searchable list, so long lists never have to be typed out.
public struct SearchPicker: View {
    private let items: [PickerItem]
    private let isLoading: Bool
    private let placeholder: LocalizedStringKey
    private let selectionTitle: (String) -> String
    private let onOpen: () async -> Void
    private let footer: (title: LocalizedStringKey, action: () -> Void)?
    @Binding private var selection: String?
    @State private var isOpen = false
    @State private var query = ""

    public init(selection: Binding<String?>, items: [PickerItem], isLoading: Bool, placeholder: LocalizedStringKey = "Choose an app",
                selectionTitle: @escaping (String) -> String = { $0 }, footer: (title: LocalizedStringKey, action: () -> Void)? = nil,
                onOpen: @escaping () async -> Void) {
        _selection = selection
        self.items = items
        self.isLoading = isLoading
        self.placeholder = placeholder
        self.selectionTitle = selectionTitle
        self.footer = footer
        self.onOpen = onOpen
    }

    public var body: some View {
        Button { isOpen = true } label: {
            HStack(spacing: Theme.Space.s2) {
                if let selection, !selection.isEmpty {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: selectionTitle(selection)).lineLimit(1)
                        if selectionTitle(selection) != selection { Text(verbatim: selection).font(Theme.Font.monoCaption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                } else {
                    Text(placeholder).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) { list }
    }

    private var results: [PickerItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let haystack = (item.title + " " + (item.subtitle ?? "") + " " + item.id).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $query).textFieldStyle(.roundedBorder).padding(Theme.Space.s3)
            Divider()
            if isLoading && items.isEmpty {
                LoadingLabel("Reading the phone").padding(Theme.Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            } else if results.isEmpty {
                Text("No matches").foregroundStyle(.secondary).padding(Theme.Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(results) { item in
                    Button { selection = item.id; isOpen = false } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: item.title)
                                if let subtitle = item.subtitle { Text(verbatim: subtitle).font(Theme.Font.monoCaption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if let badge = item.badge { Text(badge).font(Theme.Font.caption).foregroundStyle(.secondary) }
                            if item.id == selection { Image(systemName: "checkmark").foregroundStyle(Theme.Palette.accentText.color) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            if let footer {
                Divider()
                Button(footer.title) { footer.action(); isOpen = false }.buttonStyle(.link).padding(Theme.Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 340, height: 380)
        .task { await onOpen() }
    }
}
