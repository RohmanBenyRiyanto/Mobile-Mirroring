import SwiftUI
import Theme

/// The Benz mark: two slanted panels. Drawn as vectors from the brand SVG, so it is sharp at any size and takes whatever
/// colour it is given (`foregroundStyle`), which is what lets it follow light and dark mode.
public struct BrandMark: Shape {
    public init() {}

    /// The artwork's own coordinates (a 1024 × 1024 canvas, both panels moved and scaled as in the SVG layers).
    static let artwork: Path = {
        let left = SVGPath.parse("M229.8 21.5A16 16 0 0 1 255 34.5L255 550.1A16 16 0 0 1 248.2 563.2L39.2 709.5A16 16 0 0 1 14 696.4L14 182.5A16 16 0 0 1 20.8 169.5Z")
        let right = SVGPath.parse("M291 322.9A16 16 0 0 1 316.2 309.8L489.2 431.6A16 16 0 0 1 496 444.7L496 831.8A16 16 0 0 1 472.7 846.1L169.6 690.8A16 16 0 0 1 167.8 663.5L268.8 592.7A52 52 0 0 0 291 550.1Z")
        // The SVG layers place both panels with translate(301.72 168.51) scale(0.79327).
        let place = CGAffineTransform(scaleX: 0.79327, y: 0.79327).concatenating(CGAffineTransform(translationX: 301.72, y: 168.51))
        var both = Path()
        for panel in [left, right] { if let panel { both.addPath(panel, transform: place) } }
        return both
    }()

    /// The mark's own bounds in artwork coordinates.
    public static var artworkBounds: CGRect { artwork.cgPath.boundingBoxOfPath } // tight: the curves' control points are not counted

    public func path(in rect: CGRect) -> Path {
        let bounds = Self.artworkBounds
        guard bounds.width > 0, bounds.height > 0, rect.width > 0, rect.height > 0 else { return Path() }
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let transform = CGAffineTransform(translationX: rect.midX - size.width / 2 - bounds.minX * scale,
                                          y: rect.midY - size.height / 2 - bounds.minY * scale)
            .scaledBy(x: scale, y: scale)
        return Self.artwork.applying(transform)
    }
}

/// The three looks of the app icon (the design's icon board).
public enum BrandVariant: String, CaseIterable, Identifiable {
    case darkBlue = "A-dark-blue"
    case clearBlue = "B-clear-blue"
    case light = "C-light"

    public var id: String { rawValue }

    public var title: LocalizedStringKey {
        switch self {
        case .darkBlue: return "Dark Blue"
        case .clearBlue: return "Clear Blue"
        case .light: return "Light"
        }
    }
}

/// How the brand is drawn: flat vector, or with the glass effect.
public enum BrandStyle: String, CaseIterable, Identifiable {
    case flat, glass

    public var id: String { rawValue }
}

/// The mark in the text colour (dark ink in light mode, near white in dark mode), or as glass.
public struct BrandLogo: View {
    private let height: CGFloat
    private let style: BrandStyle

    public init(height: CGFloat = 32, style: BrandStyle = .flat) {
        self.height = height
        self.style = style
    }

    public var body: some View {
        Group {
            switch style {
            case .flat: BrandMark().fill(Theme.Palette.text.color)
            case .glass: GlassMark()
            }
        }
        .aspectRatio(BrandMark.artworkBounds.width / BrandMark.artworkBounds.height, contentMode: .fit)
        .frame(height: height)
        .accessibilityLabel("Benz Mirror")
    }
}

/// The mark as a sheet of glass: the system's own Liquid Glass on macOS 26+, an imitation (a pale gradient, a bright edge and
/// a soft shadow) before, and a plain fill when the user chose solid surfaces.
struct GlassMark: View {
    var body: some View {
        switch SurfaceStyle.rendering {
        case .realGlass:
            if #available(macOS 26, *) {
                BrandMark().fill(Color.clear).glassEffect(.regular, in: BrandMark())
            } else {
                imitation
            }
        case .emulatedGlass, .material:
            imitation
        case .solid:
            BrandMark().fill(Theme.Palette.text.color)
        }
    }

    private var imitation: some View {
        BrandMark()
            .fill(LinearGradient(colors: [.white.opacity(0.75), Color.accentColor.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(BrandMark().stroke(.white.opacity(0.85), lineWidth: 1))
            .overlay(BrandMark().stroke(Theme.Palette.glassRim, lineWidth: 0.5).blur(radius: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

/// The app icon as a tile, for places inside the app (welcome screen, About, Settings).
///
/// Flat: drawn in code. Glass: the design's 3D glass render, three layers (background, shadow, mark) stacked on the same
/// 1024 canvas. With `variant: nil` it follows the appearance: dark blue in dark mode, the pale tile in light mode.
public struct BrandTile: View {
    private let size: CGFloat
    private let variant: BrandVariant?
    private let style: BrandStyle
    @Environment(\.colorScheme) private var colorScheme

    public init(size: CGFloat = 96, variant: BrandVariant? = nil, style: BrandStyle = .flat) {
        self.size = size
        self.variant = variant
        self.style = style
    }

    private var resolved: BrandVariant { variant ?? (colorScheme == .dark ? .darkBlue : .light) }

    /// Top and bottom of the flat tile, and the mark: the three variants of the design's icon board.
    static func colors(_ variant: BrandVariant) -> (top: Color, bottom: Color, mark: Color) {
        switch variant {
        case .clearBlue: return (Color(hex: "#5cc2ff"), Color(hex: "#004fd0"), .white)
        case .light: return (Color(hex: "#fcfdff"), Color(hex: "#d2dbe8"), Color(hex: "#0b1424"))
        case .darkBlue: return (Color(hex: "#020a1c"), Color(hex: "#0a55c8"), .white)
        }
    }

    public var body: some View {
        Group {
            switch style {
            case .flat: flat
            case .glass: glass
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var flat: some View {
        let colors = Self.colors(resolved)
        return RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(LinearGradient(colors: [colors.top, colors.bottom], startPoint: .top, endPoint: .bottom))
            // The mark is 382 x 654 on the icon's 1024 canvas, centred.
            .overlay(BrandMark().fill(colors.mark).frame(width: size * 382 / 1024, height: size * 654 / 1024))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: max(0.5, size / 256)))
    }

    private var glass: some View {
        ZStack {
            ForEach(["1-background", "2-shadow", "3-mark-glass"], id: \.self) { piece in
                Image("BrandGlass-\(resolved.rawValue)-\(piece)", bundle: .module).resizable().interpolation(.high)
            }
        }
    }
}

extension Color {
    /// `#RRGGBB`. Anything else gives clear, so a typo shows up as a missing colour rather than a crash.
    init(hex: String) {
        guard let value = HexColor(hex) else { self = .clear; return }
        self = Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: 1)
    }
}
