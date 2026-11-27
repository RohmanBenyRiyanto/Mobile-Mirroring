import AppKit
import DomainModels

extension PickedColor {
    public var swatch: NSColor { NSColor(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: 1) }
}
