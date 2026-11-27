import AppKit
import SwiftUI

/// A colour written as `#RRGGBB`, with the maths the design checks need (contrast).
public struct HexColor: Equatable {
    public let red: Double, green: Double, blue: Double

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

/// One colour with a light and a dark value. The hex strings are the single source; `color` follows the appearance.
public struct ThemeColor {
    public let light: String
    public let dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }

    public var lightValue: HexColor { HexColor(light)! }
    public var darkValue: HexColor { HexColor(dark)! }

    public var nsColor: NSColor {
        let light = lightValue.nsColor, dark = darkValue.nsColor
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    public var color: Color { Color(nsColor: nsColor) }
}

/// The design's tokens (Claude Design v2, `Tokens`). Colours come in light and dark; the accent itself is the
/// system's `Color.accentColor`, so it follows the user's choice in System Settings.
public enum Theme {
    // MARK: Colour

    public enum Palette {
        public static let window = ThemeColor(light: "#f5f5f7", dark: "#1c1d21")
        public static let card = ThemeColor(light: "#ffffff", dark: "#27282d")
        public static let control = ThemeColor(light: "#ececef", dark: "#34353b")
        public static let hover = ThemeColor(light: "#e3e3e8", dark: "#3d3e45")
        public static let hairline = ThemeColor(light: "#d9d9de", dark: "#47484f")
        /// Borders of controls (at least 3 : 1 against the surface).
        public static let controlBorder = ThemeColor(light: "#85858b", dark: "#82848d")
        public static let text = ThemeColor(light: "#1d1d1f", dark: "#f5f5f7")
        public static let textSecondary = ThemeColor(light: "#55555b", dark: "#b4b7c0")
        /// Links and sidebar icons; passes 4.5 : 1 on every surface.
        public static let accentText = ThemeColor(light: "#0059c0", dark: "#6cc0ff")
        /// Recording and errors only.
        public static let red = ThemeColor(light: "#c40f23", dark: "#ff7a7d")
        public static let redFill = ThemeColor(light: "#e9152d", dark: "#e9152d")
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

    public enum Font {
        public static let caption = SwiftUI.Font.system(size: 11)
        public static let body = SwiftUI.Font.system(size: 13)
        public static let headline = SwiftUI.Font.system(size: 15, weight: .semibold)
        public static let title = SwiftUI.Font.system(size: 22, weight: .semibold)
        /// Addresses, sizes, timers and statistics: fixed-width digits so nothing jitters.
        public static let mono = SwiftUI.Font.system(size: 12, design: .monospaced).monospacedDigit()
        public static let monoCaption = SwiftUI.Font.system(size: 11, design: .monospaced).monospacedDigit()
    }

    // MARK: Motion

    public enum Motion {
        public static let fast = 0.12, base = 0.16, slow = 0.20
    }
}
