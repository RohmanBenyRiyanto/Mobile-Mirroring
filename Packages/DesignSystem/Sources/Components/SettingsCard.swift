import SwiftUI
import Theme

// These components are the pieces of a grouped form. They are meant to sit inside a `Form` with `.formStyle(.grouped)`, so the
// system itself draws the page, the cards, the separators and the row heights, exactly as in System Settings (including the tint
// the user's desktop picture gives a window). `GroupedForm` sets that up.

/// A page of grouped sections: `Form` with the grouped style, as in System Settings.
public struct GroupedForm<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        Form { content }
            .formStyle(.grouped)
            .font(Theme.Font.body)
    }
}

/// A section of a grouped form: an optional heading above, and a card of rows.
public struct SettingsCard<Content: View>: View {
    private let title: LocalizedStringKey?
    private let footer: LocalizedStringKey?
    private let content: Content

    public init(_ title: LocalizedStringKey? = nil, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        Section {
            content
        } header: {
            if let title { Text(title) }
        } footer: {
            if let footer { Text(footer) }
        }
    }
}

/// One row of a card: a title (with an optional line under it) and a control on the trailing side.
public struct SettingsRow<Trailing: View>: View {
    private let title: LocalizedStringKey
    private let detail: LocalizedStringKey?
    private let trailing: Trailing

    public init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        LabeledContent {
            trailing
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                if let detail {
                    Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A row that carries its own look (a grid of preset cards, a message card): no card behind it, no separator, no inset.
public struct PlainRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: Theme.Space.s3, leading: Theme.Space.s3, bottom: Theme.Space.s3, trailing: Theme.Space.s3))
    }
}
