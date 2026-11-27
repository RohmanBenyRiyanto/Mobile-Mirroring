import SwiftUI
import Theme

public struct NumberedSteps: View {
    private let steps: [LocalizedStringKey]

    public init(_ steps: [LocalizedStringKey]) { self.steps = steps }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s2) {
                    Text("\(index + 1)")
                        .font(Theme.Font.monoCaption)
                        .frame(width: 18, height: 18)
                        .background(Theme.Palette.control.color, in: Circle())
                    Text(step).font(Theme.Font.body).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

public struct FieldBackground: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .font(Theme.Font.mono)
            .padding(.horizontal, Theme.Space.s2)
            .frame(height: Theme.Size.control)
            .background(Theme.Palette.control.color, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field).strokeBorder(Theme.Palette.hairline.color, lineWidth: 1))
    }
}

extension View {
    public func fieldBackground() -> some View { modifier(FieldBackground()) }
}

public struct MonoField<Trailing: View>: View {
    private let text: String
    private let trailing: Trailing

    public init(_ text: String, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Theme.Space.s2) {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fieldBackground()
            trailing
        }
    }
}
