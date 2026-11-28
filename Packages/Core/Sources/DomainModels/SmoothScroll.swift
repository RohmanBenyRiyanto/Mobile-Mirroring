import CoreGraphics
import Foundation

public struct ScrollStroke: Equatable, Sendable {
    public enum Output: Equatable, Sendable {
        case down(CGPoint)
        case move(CGPoint)
        case up(CGPoint)
    }

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

public struct ArrowScroll: Equatable, Sendable {
    public var topSpeed = 1.5
    public var rampTime = 0.12
    public var minimumTravel = 0.2

    public init() {}

    public func travel(heldFor seconds: Double) -> Double {
        let t = max(seconds, 0)
        if t < rampTime { return 0.5 * topSpeed * t * t / rampTime }
        return 0.5 * topSpeed * rampTime + topSpeed * (t - rampTime)
    }

    public func remainingAtRelease(travelled: Double) -> Double { max(minimumTravel - travelled, 0) }
}
