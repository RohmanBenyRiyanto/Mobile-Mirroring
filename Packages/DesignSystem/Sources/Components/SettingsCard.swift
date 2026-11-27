import SwiftUI
import Theme

public struct GroupedForm<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        Form { content }
            .formStyle(.grouped)
            .font(Theme.Font.body)
    }
}

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

/// A row without the card's background, separator or inset, for content such as a grid of cards.
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
