import SwiftUI
import Theme

/// A choice among a few presets (video quality): a title and one line of numbers, 60 pt tall.
/// The chosen card gets a 2 pt accent border and a check; the others have no border.
public struct PresetCard: View {
    private let title: LocalizedStringKey
    private let detail: String
    private let isSelected: Bool
    private let action: () -> Void

    /// `detail` is already formatted (numbers and units), so it is not looked up in the string catalog.
    public init(_ title: LocalizedStringKey, detail: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.s2) {
                    Text(title).font(Theme.Font.emphasized).lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.accentColor, in: Circle())
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, Theme.Space.s3)
            .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .leading)
            // A raised tile on the section's card, so it is a fill and not a second card.
            .background(Theme.Palette.control.color, in: RoundedRectangle(cornerRadius: Theme.Radius.field + 2))
            .overlay(
                // Only the chosen card has an edge; the others are told apart from the page by their fill alone.
                RoundedRectangle(cornerRadius: Theme.Radius.field + 2)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.field + 2))
        }
        .buttonStyle(.plain)
        .animated(Theme.Motion.snappy, value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
