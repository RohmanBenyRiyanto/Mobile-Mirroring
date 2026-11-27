import SwiftUI

public enum SurfaceMode: String, CaseIterable, Identifiable, Codable {
    /// Liquid Glass on macOS 26 and later, a material before.
    case automatic
    /// Liquid Glass always, imitated on systems without it.
    case glass
    case solid

    public var id: String { rawValue }
}

public enum SurfaceRendering: Equatable {
    case realGlass, emulatedGlass, material, solid
}

public enum SurfaceStyle {
    /// The user's choice, set at launch and whenever the setting changes.
    nonisolated(unsafe) public static var mode = SurfaceMode.automatic
    /// Lets tests exercise the pre-macOS 26 fallback on a Mac that has glass.
    nonisolated(unsafe) public static var allowsGlass = true

    public static var rendering: SurfaceRendering {
        let hasRealGlass: Bool
        if #available(macOS 26, *) { hasRealGlass = allowsGlass } else { hasRealGlass = false }
        switch mode {
        case .solid: return .solid
        case .automatic: return hasRealGlass ? .realGlass : .material
        case .glass: return hasRealGlass ? .realGlass : .emulatedGlass
        }
    }
}

/// Identifies a glass surface so it can morph into another one.
public struct GlassMorph {
    let id: String
    let namespace: Namespace.ID

    public init(id: String, in namespace: Namespace.ID) {
        self.id = id
        self.namespace = namespace
    }
}

/// Groups glass surfaces that appear together. Real glass uses a `GlassEffectContainer` so they blend and morph; elsewhere it does nothing.
public struct GlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if SurfaceStyle.rendering == .realGlass, #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// A floating or navigation surface (rail, toolbar group, toast, tooltip).
    ///
    /// Apply it after the modifiers that change how the view looks (padding, frame): glass captures what is drawn so far.
    /// - Parameter morph: lets this surface morph into another one with the same id inside a `GlassGroup`.
    @ViewBuilder
    public func glassSurface<S: InsettableShape>(in shape: S, interactive: Bool = false, tint: Color? = nil, morph: GlassMorph? = nil) -> some View {
        switch SurfaceStyle.rendering {
        case .realGlass:
            if #available(macOS 26, *) {
                let glass = Self.glass(interactive: interactive, tint: tint)
                if let morph {
                    self.glassEffect(glass, in: shape).glassEffectID(morph.id, in: morph.namespace)
                } else {
                    self.glassEffect(glass, in: shape)
                }
            } else {
                self.background(.regularMaterial, in: shape)
            }
        case .emulatedGlass:
            self.background(EmulatedGlass(shape: shape))
        case .material:
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.Palette.hairline.color.opacity(0.6), lineWidth: 1))
        case .solid:
            self.background(Theme.Palette.card.color, in: shape)
                .overlay(shape.strokeBorder(Theme.Palette.hairline.color, lineWidth: 1))
        }
    }

    @available(macOS 26, *)
    private static func glass(interactive: Bool, tint: Color?) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    @ViewBuilder
    public func prominentAction() -> some View {
        if SurfaceStyle.rendering == .realGlass, #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder
    public func secondaryAction() -> some View {
        if SurfaceStyle.rendering == .realGlass, #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }

    /// Uses a solid scrim rather than glass, since blur over moving video costs GPU time.
    public func overVideo<S: Shape>(in shape: S) -> some View {
        self.foregroundStyle(Theme.OverVideo.text).background(Theme.OverVideo.scrim, in: shape)
    }

    public func card(radius: CGFloat = Theme.Radius.card) -> some View {
        self.background(Theme.Palette.card.color, in: RoundedRectangle(cornerRadius: radius))
    }
}

/// Imitates Liquid Glass with a blurred body, a highlight along the top and a hairline rim.
struct EmulatedGlass<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Theme.Palette.glassTint))
            .overlay(shape.strokeBorder(Theme.Palette.glassRim, lineWidth: 0.5))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Theme.Palette.glassHighlight, .clear, .clear, Theme.Palette.glassRim.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
    }
}
