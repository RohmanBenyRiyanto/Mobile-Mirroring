import Foundation

public struct PinchGesture: Equatable {
    private let frameWidth: UInt16
    private let frameHeight: UInt16
    private let centerX: Int32
    private let centerY: Int32
    private let minimumSpread = 12.0
    public private(set) var spread: Double

    public init(center: TouchPosition) {
        frameWidth = center.frameWidth
        frameHeight = center.frameHeight
        centerX = center.x
        centerY = center.y
        spread = max(Double(min(center.frameWidth, center.frameHeight)) * 0.1, minimumSpread)
    }

    public var fingers: (first: TouchPosition, second: TouchPosition) {
        let offset = Int32(spread.rounded())
        return (point(x: centerX - offset), point(x: centerX + offset))
    }

    public mutating func scale(by factor: Double) {
        let limit = Double(frameWidth) / 2
        spread = min(max(spread * max(factor, 0.1), minimumSpread), limit)
    }

    public static func mirrored(_ position: TouchPosition) -> TouchPosition {
        TouchPosition(x: Int32(position.frameWidth) - 1 - position.x,
                      y: Int32(position.frameHeight) - 1 - position.y,
                      frameWidth: position.frameWidth, frameHeight: position.frameHeight)
    }

    private func point(x: Int32) -> TouchPosition {
        TouchPosition(x: min(max(x, 0), Int32(frameWidth) - 1), y: centerY, frameWidth: frameWidth, frameHeight: frameHeight)
    }
}
