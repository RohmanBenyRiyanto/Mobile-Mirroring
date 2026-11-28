import CoreGraphics
import Foundation

/// Sizes for the flexible virtual display. Pure, so the rules are tested without a phone.
public enum VirtualDisplayMath {
    public static let initialSize = initialSize(landscape: false)

    /// Where the display starts. Games that insist on landscape would otherwise start portrait and flip a moment later,
    /// so the shape an app turned out to want is remembered and used the next time.
    public static func initialSize(landscape: Bool) -> (width: Int, height: Int) { landscape ? (1920, 1080) : (1080, 1920) }
    /// Games and apps are drawn for about this many dp across the short edge of a phone.
    static let phoneShortEdgeDP = 411.0
    static let step = 8
    static let minimumEdge = 320

    /// The display size for a window: its pixels, shrunk to the encoder's longest edge if needed, in multiples of 8 (what hardware encoders like).
    public static func size(forViewPoints view: CGSize, backingScale: CGFloat, maxLongEdge: Int) -> (width: UInt16, height: UInt16)? {
        guard view.width >= 1, view.height >= 1, backingScale > 0 else { return nil }
        var width = Double(view.width * backingScale), height = Double(view.height * backingScale)
        let longEdge = max(width, height)
        if longEdge > Double(maxLongEdge) {
            let shrink = Double(maxLongEdge) / longEdge
            width *= shrink
            height *= shrink
        }
        func snap(_ value: Double) -> Int { max(Int(value) / step * step, minimumEdge) }
        let w = snap(width), h = snap(height)
        guard w <= Int(UInt16.max), h <= Int(UInt16.max) else { return nil }
        return (UInt16(w), UInt16(h))
    }

    /// The longest edge the display may have. "Native" (0) means no limit from the quality setting, so a sensible ceiling stands in:
    /// treating 0 as a limit would shrink the display to the smallest size and blur everything.
    public static func longestEdge(forMaxSize maxSize: Int) -> Int { maxSize > 0 ? maxSize : 2560 }

    /// A density that gives the apps about the width of a phone to draw on, so layouts look as they do on the phone.
    public static func density(shortEdge: Int) -> Int {
        min(max(Int((Double(shortEdge) * 160 / phoneShortEdgeDP).rounded()), 120), 640)
    }

    /// Resizing on every pixel of a window drag would restart the encoder constantly; only real changes pass.
    public static func isWorthSending(old: (width: UInt16, height: UInt16)?, new: (width: UInt16, height: UInt16)) -> Bool {
        guard let old else { return true }
        return abs(Int(old.width) - Int(new.width)) >= 16 || abs(Int(old.height) - Int(new.height)) >= 16
    }
}
