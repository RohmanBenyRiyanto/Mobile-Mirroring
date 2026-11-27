import SwiftUI

// Liquid Glass exists on macOS 26 and later. Older systems get the same layout with a material or a plain fill,
// so every screen is built from these helpers and never checks the version itself.

/// Lets tests draw the pre-macOS-26 look on a Mac that has glass, so the fallback is checked too.
public enum SurfaceStyle {
    nonisolated(unsafe) public static var allowsGlass = true
}

private var useGlass: Bool {
    if #available(macOS 26, *) { return SurfaceStyle.allowsGlass }
    return false
}

extension View {
    /// A floating or navigation surface (rail, toolbar group, toast, tooltip): glass on macOS 26+, a material before.
    @ViewBuilder
    public func glassSurface<S: Shape>(in shape: S) -> some View {
        if useGlass, #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Theme.Palette.hairline.color.opacity(0.6), lineWidth: 1))
        }
    }

    /// The one prominent action of a window or sheet.
    @ViewBuilder
    public func prominentAction() -> some View {
        if useGlass, #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }

    /// A secondary button next to the prominent one.
    @ViewBuilder
    public func secondaryAction() -> some View {
        if useGlass, #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }

    /// Text or marks over the live video: a solid scrim, never glass (blur over moving video costs GPU time and delay).
    public func overVideo<S: Shape>(in shape: S) -> some View {
        self.foregroundStyle(Theme.OverVideo.text).background(Theme.OverVideo.scrim, in: shape)
    }

    /// A grouped card on the window background: solid, with a hairline.
    public func card(radius: CGFloat = Theme.Radius.card) -> some View {
        self.background(Theme.Palette.card.color, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.Palette.hairline.color, lineWidth: 1))
    }
}
