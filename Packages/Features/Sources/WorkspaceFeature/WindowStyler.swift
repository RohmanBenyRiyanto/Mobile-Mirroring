import AppKit
import SwiftUI

/// Adjusts the hosting window: a chrome-free, aspect-locked window in stream mode (clean for OBS
/// window capture), and an optional always-on-top level.
public struct WindowStyler: NSViewRepresentable {
    public let isStreamMode: Bool
    public let alwaysOnTop: Bool
    public let videoSize: CGSize

    public init(isStreamMode: Bool, alwaysOnTop: Bool, videoSize: CGSize) {
        self.isStreamMode = isStreamMode
        self.alwaysOnTop = alwaysOnTop
        self.videoSize = videoSize
    }

    public func makeNSView(context: Context) -> NSView { NSView() }

    public func updateNSView(_ view: NSView, context: Context) {
        // The window only exists once the view is attached, so apply on the next turn of the run loop.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = alwaysOnTop ? .floating : .normal
            applyChrome(to: window)
        }
    }

    private func applyChrome(to window: NSWindow) {
        window.titlebarAppearsTransparent = isStreamMode
        window.titleVisibility = isStreamMode ? .hidden : .visible
        window.isMovableByWindowBackground = isStreamMode
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = isStreamMode
        }

        if isStreamMode {
            window.styleMask.insert(.fullSizeContentView)
            window.contentAspectRatio = videoSize
        } else {
            window.styleMask.remove(.fullSizeContentView)
            window.resizeIncrements = NSSize(width: 1, height: 1) // also clears the aspect ratio
        }
    }
}

public enum StreamWindow {
    /// Sizes the key window so one video pixel is one screen pixel, shrunk to fit the screen if needed.
    @MainActor
    public static func resizeToActualPixels(videoSize: CGSize) {
        guard let window = NSApp.keyWindow, let screen = window.screen, videoSize.width > 0, videoSize.height > 0 else { return }
        let scale = window.backingScaleFactor
        let natural = CGSize(width: videoSize.width / scale, height: videoSize.height / scale)
        let available = screen.visibleFrame.size
        let shrink = min(1, available.width / natural.width, (available.height - 40) / natural.height)
        window.setContentSize(CGSize(width: natural.width * shrink, height: natural.height * shrink))
    }
}
