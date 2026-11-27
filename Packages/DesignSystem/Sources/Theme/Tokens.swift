import AppKit
import SwiftUI

/// A colour written as `#RRGGBB`, with the maths the design checks need (contrast).
public struct HexColor: Equatable {
    public let red: Double, green: Double, blue: Double

    /// From sRGB components (0…1).
    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(_ hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two colours (1…21).
    public static func contrast(_ a: HexColor, _ b: HexColor) -> Double {
        let (light, dark) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (light + 0.05) / (dark + 0.05)
    }

    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

/// A colour that follows the appearance. Either one of the system's own colours, or a brand colour given as two hex values.
public struct ThemeColor {
    public let nsColor: NSColor

    /// One of the system's semantic colours (`labelColor`, `separatorColor`, …). Light, dark, increased contrast, vibrancy and
    /// the desktop tint of the window are all handled by the system.
    public init(system color: NSColor) { nsColor = color }

    /// A brand colour, written as two hex values (light and dark).
    public init(light: String, dark: String) {
        let (lightColor, darkColor) = (HexColor(light)!.nsColor, HexColor(dark)!.nsColor)
        nsColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor }
    }

    /// Chooses between two system colours by appearance.
    public init(light: NSColor, dark: NSColor) {
        nsColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    public var color: Color { Color(nsColor: nsColor) }

    /// The colour as it looks in an appearance, as sRGB with its transparency.
    public func resolved(in appearance: NSAppearance.Name) -> NSColor {
        var result = nsColor
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            result = nsColor.usingColorSpace(.sRGB) ?? nsColor
        }
        return result
    }
}

/// Colours, spacing, type and motion. Colours are the system's own semantic colours (HIG: "avoid hard-coding system color values"),
/// so the interface matches System Settings and every other Mac app in light, dark, increased contrast and with any accent.
/// Only the brand (icon tiles) and the imitation of glass keep fixed values.
public enum Theme {
    // MARK: Colour

    public enum Palette {
        /// The page behind grouped content: `underPageBackgroundColor`.
        public static let page = ThemeColor(system: .underPageBackgroundColor)
        /// A window's own background, for windows that are not grouped forms.
        public static let window = ThemeColor(system: .windowBackgroundColor)
        /// A grouped card. In light it is the white control background on the grey page; in dark a faint lift of the page,
        /// measured from System Settings (page 42, card 51 of 255). No border: the difference in tone is the edge.
        public static let card = ThemeColor(light: .controlBackgroundColor, dark: .tertiarySystemFill)
        /// Fills of small controls and badges (a key cap, a step number), and the same when hovered or pressed.
        public static let control = ThemeColor(system: .secondarySystemFill)
        public static let hover = ThemeColor(system: .systemFill)
        /// Lines between rows, and the faint edge of a field.
        public static let hairline = ThemeColor(system: .separatorColor)
        public static let controlBorder = ThemeColor(system: .separatorColor)
        public static let text = ThemeColor(system: .labelColor)
        public static let textSecondary = ThemeColor(system: .secondaryLabelColor)
        /// Sidebar icons and links: the user's accent.
        public static let accentText = ThemeColor(system: .controlAccentColor)
        /// Recording and errors only.
        public static let red = ThemeColor(system: .systemRed)
        public static let redFill = ThemeColor(system: .systemRed)
        /// Neutral fill for a chosen or hovered tool (rail button, tab).
        public static let selection = Color(nsColor: .secondarySystemFill)
        /// The body of a glass surface and its edges (design tokens `material.glass`, `glassHighlight`, `glassRim`).
        public static let glassTint = alpha(light: (250, 252, 255, 0.68), dark: (40, 46, 62, 0.66))
        public static let glassHighlight = alpha(light: (255, 255, 255, 0.95), dark: (255, 255, 255, 0.40))
        public static let glassRim = alpha(light: (10, 30, 70, 0.14), dark: (255, 255, 255, 0.18))

        /// A colour with transparency that changes with the appearance; the values are 0…255 and an alpha.
        static func alpha(light: (Double, Double, Double, Double), dark: (Double, Double, Double, Double)) -> Color {
            func ns(_ v: (Double, Double, Double, Double)) -> NSColor { NSColor(srgbRed: v.0 / 255, green: v.1 / 255, blue: v.2 / 255, alpha: v.3) }
            let (l, d) = (ns(light), ns(dark))
            return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l })
        }

    }

    /// Text and marks drawn over the live video: the same in both appearances.
    public enum OverVideo {
        public static let scrim = Color(red: 12 / 255, green: 14 / 255, blue: 20 / 255).opacity(0.72)
        public static let text = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    }

    // MARK: Layout

    public enum Space {
        public static let inset: CGFloat = 2
        public static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16
        public static let s5: CGFloat = 20, s6: CGFloat = 24, s8: CGFloat = 32, s12: CGFloat = 48
    }

    public enum Radius {
        public static let field: CGFloat = 8
        public static let card: CGFloat = 12
        public static let window: CGFloat = 16
        public static let sheet: CGFloat = 24
        public static let rail: CGFloat = 26
    }

    public enum Size {
        public static let connectWindow = CGSize(width: 760, height: 512)
        public static let connectMinimum = CGSize(width: 360, height: 480)
        public static let sidebar: CGFloat = 208
        public static let rail: CGFloat = 52
        public static let railButton = CGSize(width: 40, height: 36)
        public static let control: CGFloat = 28
        public static let inspectorPanel: CGFloat = 300
        public static let keymapPanel: CGFloat = 280
    }

    // MARK: Type

    /// Type: the system's own text styles, so the interface reads like any other Mac app. On macOS (HIG, Typography):
    /// body 13, subheadline 11, title 3 15, title 1 22, all Regular; Medium or Semibold only to emphasise.
    /// Tracking is left to the system, which adjusts it for every size.
    public enum Font {
        public static let caption = SwiftUI.Font.subheadline
        public static let body = SwiftUI.Font.body
        /// A label that needs a little more weight than its neighbours (a card title, a step name).
        public static let emphasized = SwiftUI.Font.body.weight(.medium)
        public static let headline = SwiftUI.Font.title3.weight(.medium)
        public static let title = SwiftUI.Font.title.weight(.medium)
        /// Addresses, sizes, timers and statistics: fixed-width digits so nothing jitters.
        public static let mono = SwiftUI.Font.system(.body, design: .monospaced).monospacedDigit()
        public static let monoCaption = SwiftUI.Font.system(.subheadline, design: .monospaced).monospacedDigit()
    }

    // MARK: Motion

    public enum Motion {
        public static let fast = 0.12, base = 0.16, slow = 0.20
        /// The system's smooth spring, for content that appears, disappears or changes size.
        public static let smooth = Animation.smooth(duration: 0.28)
        /// Quicker, for small state changes (a selection border, a check mark).
        public static let snappy = Animation.snappy(duration: 0.18)
    }
}
