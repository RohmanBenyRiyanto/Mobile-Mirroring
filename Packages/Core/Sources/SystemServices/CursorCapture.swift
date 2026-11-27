import CoreGraphics
import Foundation

/// Locks and hides the Mac's mouse pointer while free-look is on. Behind a protocol so tests never
/// take hold of the real pointer.
@MainActor
public protocol CursorCapturing: AnyObject {
    func setCaptured(_ captured: Bool)
}

/// Detaches the pointer from the mouse (movement still reaches the app as deltas) and hides it.
/// Calls are balanced: hiding twice would need two shows to undo.
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
