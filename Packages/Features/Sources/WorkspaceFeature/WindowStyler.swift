import AppKit
import SwiftUI
import Theme

/// Adjusts the hosting window: a chrome-free, aspect-locked window in stream mode (clean for OBS
/// window capture), and an optional always-on-top level.
public struct WindowStyler: NSViewRepresentable {
    public let isStreamMode: Bool
    public let alwaysOnTop: Bool
    public let videoSize: CGSize
    /// Keep the window the shape of the phone's picture (the mirror window).
    public let locksAspect: Bool

    public init(isStreamMode: Bool, alwaysOnTop: Bool, videoSize: CGSize, locksAspect: Bool = false) {
        self.isStreamMode = isStreamMode
        self.alwaysOnTop = alwaysOnTop
        self.videoSize = videoSize
        self.locksAspect = locksAspect
    }

    public func makeNSView(context: Context) -> NSView { NSView() }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// Remembers the Connect window's size while the window takes the phone's shape, and the phone window's height for next time.
    @MainActor
    public final class Coordinator {
        var memory = WindowSizeMemory()
    }

    public func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        // The window only exists once the view is attached, so apply on the next turn of the run loop.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = alwaysOnTop ? .floating : .normal
            applyChrome(to: window, coordinator: coordinator)
        }
    }

    @MainActor
    private func applyChrome(to window: NSWindow, coordinator: Coordinator) {
        window.titlebarAppearsTransparent = isStreamMode
        window.titleVisibility = isStreamMode ? .hidden : .visible
        window.isMovableByWindowBackground = isStreamMode
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = isStreamMode
        }

        if isStreamMode { window.styleMask.insert(.fullSizeContentView) } else { window.styleMask.remove(.fullSizeContentView) }

        let locked = (isStreamMode || locksAspect) && videoSize.width > 0 && videoSize.height > 0
        let current = window.contentLayoutRect.size
        let available = window.screen?.visibleFrame.height ?? 900
        let target = coordinator.memory.update(isPhoneShaped: locked, currentContentSize: current, availableHeight: available,
                                               pictureRatio: locked ? videoSize.width / videoSize.height : nil)
        if locked {
            window.contentAspectRatio = videoSize
        } else {
            window.resizeIncrements = NSSize(width: 1, height: 1) // also clears the aspect ratio
        }
        if let target { resize(window, toContent: target) }
    }

    /// Animated, keeping the top-left corner where it is, so the window grows or shrinks into the new shape instead of jumping.
    private func resize(_ window: NSWindow, toContent size: CGSize) {
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

/// Decides what size the window should have as it moves between the Connect screen (always the same size, 760 × 512 at first
/// and wherever the user left it after) and the phone window (the shape of the picture, at the height it was last used).
/// Pure, so the rules are tested without a window.
struct WindowSizeMemory: Equatable {
    static let defaultConnectSize = Theme.Size.connectWindow
    /// The phone window's content height when nothing was remembered: the design's 818 pt, kept clear of the screen's edges.
    static let defaultPhoneHeight: CGFloat = 818

    private(set) var connectSize: CGSize?
    private(set) var phoneHeight: CGFloat?
    private var wasPhoneShaped = false
    private var hasSeenAWindow = false

    /// The content size to give the window now, or nil to leave it.
    mutating func update(isPhoneShaped: Bool, currentContentSize current: CGSize, availableHeight: CGFloat, pictureRatio: CGFloat?) -> CGSize? {
        defer { wasPhoneShaped = isPhoneShaped; hasSeenAWindow = true }
        guard current.width > 0, current.height > 0 else { return nil }

        if isPhoneShaped, let ratio = pictureRatio, ratio > 0 {
            if !wasPhoneShaped {
                connectSize = hasSeenAWindow ? current : (connectSize ?? Self.defaultConnectSize) // leaving Connect: remember it
                return phoneSize(height: phoneHeight ?? Self.defaultPhoneHeight, ratio: ratio, availableHeight: availableHeight)
            }
            // Already a phone window: only follow a change of the picture's shape (the phone rotated).
            guard abs(current.width / current.height - ratio) > 0.01 else { return nil }
            return phoneSize(height: current.height, ratio: ratio, availableHeight: availableHeight)
        }

        if wasPhoneShaped {
            phoneHeight = current.height // leaving the phone window: remember its height
            return connectSize ?? Self.defaultConnectSize
        }
        // The very first look at the window: always start at the Connect size, whatever frame was restored from last time.
        if !hasSeenAWindow, abs(current.width - Self.defaultConnectSize.width) > 1 || abs(current.height - Self.defaultConnectSize.height) > 1 {
            return Self.defaultConnectSize
        }
        return nil
    }

    private func phoneSize(height wanted: CGFloat, ratio: CGFloat, availableHeight: CGFloat) -> CGSize {
        let height = max(360, min(wanted, availableHeight - 80))
        return CGSize(width: (height * ratio).rounded(), height: height.rounded())
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
