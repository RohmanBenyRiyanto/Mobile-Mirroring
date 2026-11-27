import AppKit

/// Waits for the next key press anywhere in the app, so the user can choose a key by pressing it.
@MainActor
public enum KeyCapture {
    /// The virtual key code of the next key pressed, or nil if Escape was pressed to cancel.
    public static func next() async -> UInt16? {
        await withCheckedContinuation { continuation in
            var monitor: Any?
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if let monitor { NSEvent.removeMonitor(monitor) }
                continuation.resume(returning: event.keyCode == 53 ? nil : event.keyCode)
                return nil // the key is only a choice, it must not also reach the phone
            }
        }
    }
}
