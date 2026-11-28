import CoreGraphics
import Foundation

@MainActor
public protocol CursorCapturing: AnyObject {
    func setCaptured(_ captured: Bool)
}

@MainActor
public final class SystemCursorCapture: CursorCapturing {
    public init() {}

    private var isCaptured = false

    public func setCaptured(_ captured: Bool) {
        guard captured != isCaptured else { return }
        isCaptured = captured
        CGAssociateMouseAndMouseCursorPosition(captured ? 0 : 1)
        if captured { CGDisplayHideCursor(CGMainDisplayID()) } else { CGDisplayShowCursor(CGMainDisplayID()) }
    }
}
