import AppKit

@MainActor
public enum KeyCapture {
    public static func next() async -> UInt16? {
        await withCheckedContinuation { continuation in
            var monitor: Any?
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if let monitor { NSEvent.removeMonitor(monitor) }
                continuation.resume(returning: event.keyCode == 53 ? nil : event.keyCode)
                return nil
            }
        }
    }
}
