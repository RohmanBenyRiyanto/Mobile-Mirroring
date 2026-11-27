import CoreGraphics
import Foundation

/// One finger dragged across the phone's screen, in 0…1 screen ratios. Android turns the release into a fling,
/// so feeds scroll the way they do under a real finger instead of in the steps a mouse wheel gives.
public struct ScrollStroke: Equatable, Sendable {
    public enum Output: Equatable, Sendable {
        case down(CGPoint)
        case move(CGPoint)
        case up(CGPoint)
    }

    /// The finger stays inside this band so it never leaves the screen or hits the system gesture edges.
    public static let safeRange: ClosedRange<CGFloat> = 0.06...0.94

    public private(set) var position: CGPoint?
    public var isDown: Bool { position != nil }

    public init() {}

    public static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, safeRange.lowerBound), safeRange.upperBound), y: min(max(point.y, safeRange.lowerBound), safeRange.upperBound))
    }

    public mutating func begin(at point: CGPoint) -> [Output] {
        guard position == nil else { return [] }
        let start = Self.clamp(point)
        position = start
        return [.down(start)]
    }

    public mutating func move(by delta: CGVector) -> [Output] {
        guard let current = position, delta.dx != 0 || delta.dy != 0 else { return [] }
        let next = Self.clamp(CGPoint(x: current.x + delta.dx, y: current.y + delta.dy))
        guard next != current else { return [] }
        position = next
        return [.move(next)]
    }

    public mutating func end() -> [Output] {
        guard let last = position else { return [] }
        position = nil
        return [.up(last)]
    }
}

/// How far a held arrow key drags the finger: it speeds up smoothly, then holds a steady pace, and a quick tap still moves a visible step.
public struct ArrowScroll: Equatable, Sendable {
    /// Screen heights per second once up to speed.
    public var topSpeed = 1.5
    /// Seconds to reach top speed.
    public var rampTime = 0.12
    /// The least a tap moves, as a fraction of the screen.
    public var minimumTravel = 0.2

    public init() {}

    /// Distance covered after the key has been held for `seconds`.
    public func travel(heldFor seconds: Double) -> Double {
        let t = max(seconds, 0)
        if t < rampTime { return 0.5 * topSpeed * t * t / rampTime }
        return 0.5 * topSpeed * rampTime + topSpeed * (t - rampTime)
    }

    /// What is still owed when the key is released, so a tap is never smaller than `minimumTravel`.
    public func remainingAtRelease(travelled: Double) -> Double { max(minimumTravel - travelled, 0) }
}
