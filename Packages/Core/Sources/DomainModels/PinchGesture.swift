import Foundation

/// Geometry of a two-finger pinch on the device screen, so zoom and rotate gestures
/// can be driven by a trackpad pinch or by Option + drag.
public struct PinchGesture: Equatable {
    private let frameWidth: UInt16
    private let frameHeight: UInt16
    private let centerX: Int32
    private let centerY: Int32
    private let minimumSpread = 12.0
    /// Half the distance between the two fingers, in frame pixels.
    public private(set) var spread: Double

    /// Starts with the fingers slightly apart, centered on `center`.
    public init(center: TouchPosition) {
        frameWidth = center.frameWidth
        frameHeight = center.frameHeight
        centerX = center.x
        centerY = center.y
        spread = max(Double(min(center.frameWidth, center.frameHeight)) * 0.1, minimumSpread)
    }

    /// The two finger positions, side by side around the center and kept inside the frame.
    public var fingers: (first: TouchPosition, second: TouchPosition) {
        let offset = Int32(spread.rounded())
        return (point(x: centerX - offset), point(x: centerX + offset))
    }

    /// Spreads (factor > 1) or closes (factor < 1) the fingers.
    public mutating func scale(by factor: Double) {
        let limit = Double(frameWidth) / 2
        spread = min(max(spread * max(factor, 0.1), minimumSpread), limit)
    }

    /// The point opposite `position` through the center of the frame (second finger of an Option + drag pinch).
    public static func mirrored(_ position: TouchPosition) -> TouchPosition {
        TouchPosition(x: Int32(position.frameWidth) - 1 - position.x,
                      y: Int32(position.frameHeight) - 1 - position.y,
                      frameWidth: position.frameWidth, frameHeight: position.frameHeight)
    }

    private func point(x: Int32) -> TouchPosition {
        TouchPosition(x: min(max(x, 0), Int32(frameWidth) - 1), y: centerY, frameWidth: frameWidth, frameHeight: frameHeight)
    }
}
