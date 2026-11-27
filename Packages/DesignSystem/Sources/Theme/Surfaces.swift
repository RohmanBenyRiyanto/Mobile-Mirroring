import SwiftUI

// Liquid Glass exists on macOS 26 and later. Everything is built from these helpers, so no screen checks the system version
// itself, and the user's choice of style (Settings › Appearance) is honoured in one place.

/// How floating and navigation surfaces (rail, toolbar groups, toasts, tooltips) are drawn.
public enum SurfaceMode: String, CaseIterable, Identifiable, Codable {
    /// Liquid Glass where the system has it, a material before.
    case automatic
    /// Liquid Glass always: the system's own on macOS 26+, a close imitation (blur, highlight, rim) before.
    case glass
    /// Plain solid surfaces, no transparency.
    case solid

    public var id: String { rawValue }
}

/// What a surface is actually drawn with, after the user's choice and the system's abilities are put together.
public enum SurfaceRendering: Equatable {
    case realGlass, emulatedGlass, material, solid
}

public enum SurfaceStyle {
    /// The user's choice. Set once at launch and whenever the setting changes.
    nonisolated(unsafe) public static var mode = SurfaceMode.automatic
    /// Lets tests draw the pre-macOS-26 look on a Mac that has glass, so the fallback is checked too.
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

/// Names a glass surface so it can morph into another one (a rail that folds into a tab) when the view changes.
public struct GlassMorph {
    let id: String
    let namespace: Namespace.ID

    public init(id: String, in namespace: Namespace.ID) {
        self.id = id
        self.namespace = namespace
    }
}

/// Groups glass surfaces that appear together. On macOS 26 with real glass this is a `GlassEffectContainer`: one render pass
/// for the whole group, and surfaces that are close blend and morph into each other. Elsewhere it changes nothing.
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
    /// - Parameters:
    ///   - interactive: the glass reacts to the pointer like a glass button does.
    ///   - tint: suggests prominence on real glass.
    ///   - morph: lets this surface morph into another one with the same id inside a `GlassGroup`.
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

    /// The one prominent action of a window or sheet.
    @ViewBuilder
    public func prominentAction() -> some View {
        if SurfaceStyle.rendering == .realGlass, #available(macOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }

    /// A secondary button next to the prominent one.
    @ViewBuilder
    public func secondaryAction() -> some View {
        if SurfaceStyle.rendering == .realGlass, #available(macOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }

    /// Text or marks over the live video: a solid scrim, never glass (blur over moving video costs GPU time and delay).
    public func overVideo<S: Shape>(in shape: S) -> some View {
        self.foregroundStyle(Theme.OverVideo.text).background(Theme.OverVideo.scrim, in: shape)
    }

    /// A grouped card on the page: a solid fill a little lighter than the page, and no border (as in System Settings).
    public func card(radius: CGFloat = Theme.Radius.card) -> some View {
        self.background(Theme.Palette.card.color, in: RoundedRectangle(cornerRadius: radius))
    }
}

/// Liquid Glass imitated for systems that do not have it, from the design's own recipe: a blurred, tinted body, a bright
/// inner edge along the top, a faint dark edge along the bottom, and a hairline rim.
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
