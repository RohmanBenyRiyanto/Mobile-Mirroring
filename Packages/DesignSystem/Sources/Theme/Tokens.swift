import AppKit
import SwiftUI

/// An sRGB colour parsed from `#RRGGBB`, with WCAG luminance and contrast.
public struct HexColor: Equatable {
    public let red: Double, green: Double, blue: Double

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

    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, from 1 to 21.
    public static func contrast(_ a: HexColor, _ b: HexColor) -> Double {
        let (light, dark) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (light + 0.05) / (dark + 0.05)
    }

    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

/// A colour that follows the appearance, either a system colour or a brand colour from two hex values.
public struct ThemeColor {
    public let nsColor: NSColor

    /// The system handles appearance, increased contrast and vibrancy for this colour.
    public init(system color: NSColor) { nsColor = color }

    public init(light: String, dark: String) {
        let (lightColor, darkColor) = (HexColor(light)!.nsColor, HexColor(dark)!.nsColor)
        nsColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor }
    }

    public init(light: NSColor, dark: NSColor) {
        nsColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    public var color: Color { Color(nsColor: nsColor) }

    public func resolved(in appearance: NSAppearance.Name) -> NSColor {
        var result = nsColor
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            result = nsColor.usingColorSpace(.sRGB) ?? nsColor
        }
        return result
    }
}

/// Design tokens: colours, spacing, type and motion. Colours come from the system except for brand and glass imitation.
public enum Theme {
    // MARK: Colour

    public enum Palette {
        public static let page = ThemeColor(system: .underPageBackgroundColor)
        public static let window = ThemeColor(system: .windowBackgroundColor)
        public static let card = ThemeColor(light: .controlBackgroundColor, dark: .tertiarySystemFill)
        public static let control = ThemeColor(system: .secondarySystemFill)
        public static let hover = ThemeColor(system: .systemFill)
        public static let hairline = ThemeColor(system: .separatorColor)
        public static let controlBorder = ThemeColor(system: .separatorColor)
        public static let text = ThemeColor(system: .labelColor)
        public static let textSecondary = ThemeColor(system: .secondaryLabelColor)
        public static let accentText = ThemeColor(system: .controlAccentColor)
        public static let red = ThemeColor(system: .systemRed)
        public static let redFill = ThemeColor(system: .systemRed)
        public static let selection = Color(nsColor: .secondarySystemFill)
        public static let glassTint = alpha(light: (250, 252, 255, 0.68), dark: (40, 46, 62, 0.66))
        public static let glassHighlight = alpha(light: (255, 255, 255, 0.95), dark: (255, 255, 255, 0.40))
        public static let glassRim = alpha(light: (10, 30, 70, 0.14), dark: (255, 255, 255, 0.18))

        /// Values are 0…255 for RGB and 0…1 for alpha.
        static func alpha(light: (Double, Double, Double, Double), dark: (Double, Double, Double, Double)) -> Color {
            func ns(_ v: (Double, Double, Double, Double)) -> NSColor { NSColor(srgbRed: v.0 / 255, green: v.1 / 255, blue: v.2 / 255, alpha: v.3) }
            let (l, d) = (ns(light), ns(dark))
            return Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l })
        }

    }

    /// Fixed colours for content over video, the same in both appearances.
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

    /// Built on the system's text styles, so size and tracking adapt like any Mac app.
    public enum Font {
        public static let caption = SwiftUI.Font.subheadline
        public static let body = SwiftUI.Font.body
        public static let emphasized = SwiftUI.Font.body.weight(.medium)
        public static let headline = SwiftUI.Font.title3.weight(.medium)
        public static let title = SwiftUI.Font.title.weight(.medium)
        /// Fixed-width digits so values such as timers do not jitter.
        public static let mono = SwiftUI.Font.system(.body, design: .monospaced).monospacedDigit()
        public static let monoCaption = SwiftUI.Font.system(.subheadline, design: .monospaced).monospacedDigit()
    }

    // MARK: Motion

    public enum Motion {
        public static let fast = 0.12, base = 0.16, slow = 0.20
        public static let smooth = Animation.smooth(duration: 0.28)
        public static let snappy = Animation.snappy(duration: 0.18)
    }
}
