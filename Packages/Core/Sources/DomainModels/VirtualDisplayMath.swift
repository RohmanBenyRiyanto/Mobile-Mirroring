import CoreGraphics
import Foundation

public enum VirtualDisplayMath {
    public static let initialSize = initialSize(landscape: false)

    public static func initialSize(landscape: Bool) -> (width: Int, height: Int) { landscape ? (1920, 1080) : (1080, 1920) }
    static let phoneShortEdgeDP = 411.0
    static let step = 8
    static let minimumEdge = 320

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

    public static func longestEdge(forMaxSize maxSize: Int) -> Int { maxSize > 0 ? maxSize : 2560 }

    public static func density(shortEdge: Int) -> Int {
        min(max(Int((Double(shortEdge) * 160 / phoneShortEdgeDP).rounded()), 120), 640)
    }

    public static func isWorthSending(old: (width: UInt16, height: UInt16)?, new: (width: UInt16, height: UInt16)) -> Bool {
        guard let old else { return true }
        return abs(Int(old.width) - Int(new.width)) >= 16 || abs(Int(old.height) - Int(new.height)) >= 16
    }
}
