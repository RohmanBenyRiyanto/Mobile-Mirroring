import AppKit
import SwiftUI
import Theme

/// Styles the hosting window: chrome-free and aspect-locked in stream mode for clean OBS window capture.
/// Points at the window hosting a view, so actions on "the mirror window" never land on a helper window that happens to have focus.
@MainActor
public final class HostWindow {
    public weak var window: NSWindow?
    public init() {}
}

public struct WindowStyler: NSViewRepresentable {
    public let isStreamMode: Bool
    public let alwaysOnTop: Bool
    public let videoSize: CGSize
    public let locksAspect: Bool
    /// A phone is being mirrored (even when a side panel means the picture may not fill the window).
    public let isMirror: Bool
    /// The picture is a virtual display that follows the window, so the window is never aspect-locked.
    public let isFlexible: Bool
    public var host: HostWindow?
    /// Width taken by docked panels; if they squeeze the picture, the window grows to make room.
    public let panelWidth: CGFloat

    public init(isStreamMode: Bool, alwaysOnTop: Bool, videoSize: CGSize, locksAspect: Bool = false, isMirror: Bool = false, isFlexible: Bool = false, host: HostWindow? = nil, panelWidth: CGFloat = 0) {
        self.host = host
        self.panelWidth = panelWidth
        self.isMirror = isMirror
        self.isFlexible = isFlexible
        self.isStreamMode = isStreamMode
        self.alwaysOnTop = alwaysOnTop
        self.videoSize = videoSize
        self.locksAspect = locksAspect
    }

    public func makeNSView(context: Context) -> NSView { NSView() }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// Remembers the Connect window's size and the phone window's height between switches.
    @MainActor
    public final class Coordinator {
        var memory = WindowSizeMemory()
        var frameBeforeStreamMode: CGRect?
    }

    public func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        // The window only exists once the view is attached, so apply on the next turn of the run loop.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            host?.window = window
            window.level = alwaysOnTop ? .floating : .normal
            applyChrome(to: window, coordinator: coordinator)
        }
    }

    @MainActor
    private func applyChrome(to window: NSWindow, coordinator: Coordinator) {
        // Leaving Stream Mode puts the window back exactly where and how big it was, whatever the hidden title bar did to it.
        if isStreamMode, coordinator.frameBeforeStreamMode == nil { coordinator.frameBeforeStreamMode = window.frame }
        let restoredFrame = (!isStreamMode) ? coordinator.frameBeforeStreamMode : nil
        if !isStreamMode { coordinator.frameBeforeStreamMode = nil }
        window.titlebarAppearsTransparent = isStreamMode
        window.titleVisibility = isStreamMode ? .hidden : .visible
        window.isMovableByWindowBackground = isStreamMode
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = isStreamMode
        }

        if isStreamMode { window.styleMask.insert(.fullSizeContentView) } else { window.styleMask.remove(.fullSizeContentView) }

        if let restoredFrame {
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            window.setFrame(visible.map { WindowPlacement.fitted(restoredFrame, in: $0) } ?? restoredFrame, display: true, animate: false)
        }
        let validVideo = videoSize.width > 0 && videoSize.height > 0
        let locked = (isStreamMode || locksAspect) && !isFlexible && validVideo
        let phoneShaped = (isStreamMode || locksAspect || isMirror) && validVideo
        let fit: WindowSizeMemory.PictureFit = locked ? .locked : (isFlexible ? .orientation : .free)
        let current = window.contentLayoutRect.size
        let available = window.screen?.visibleFrame.height ?? 900
        let target = coordinator.memory.update(isPhoneShaped: phoneShaped, currentContentSize: current, availableHeight: available,
                                               pictureRatio: phoneShaped ? videoSize.width / videoSize.height : nil, fit: fit)
        if locked {
            window.contentAspectRatio = videoSize
        } else {
            window.resizeIncrements = NSSize(width: 1, height: 1) // also clears the aspect ratio
        }
        if let target { resize(window, toContent: target) }
        else if panelWidth > 0, isMirror, !isStreamMode, validVideo, !window.styleMask.contains(.fullScreen) {
            // A panel opened without the window making room (or the window was shrunk by hand): give the picture back its width.
            let content = window.contentLayoutRect.size
            let wanted = content.height * videoSize.width / videoSize.height
            let shown = content.width - panelWidth
            if shown < wanted * 0.6 {
                var frame = window.frame
                frame.size.width += wanted - shown
                if let visible = (window.screen ?? NSScreen.main)?.visibleFrame { frame = WindowPlacement.fitted(frame, in: visible) }
                window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        }
    }

    /// Animates the resize from the top-left corner so the window does not jump.
    private func resize(_ window: NSWindow, toContent size: CGSize) {
        let outer = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let frame = WindowPlacement.resized(window.frame, to: outer, in: (window.screen ?? NSScreen.main)?.visibleFrame)
        window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

/// Decides the window size as it moves between the Connect screen and the phone window. Pure, so it is tested without a window.
struct WindowSizeMemory: Equatable {
    static let defaultConnectSize = Theme.Size.connectWindow
    /// Phone window height used until one is remembered.
    static let defaultPhoneHeight: CGFloat = 818

    private(set) var connectSize: CGSize?
    private(set) var phoneHeight: CGFloat?
    private var wasPhoneShaped = false
    private var hasSeenAWindow = false

    /// The content size to give the window now, or nil to leave it.
    /// How a window that is already phone-shaped follows the picture.
    enum PictureFit { case locked, free, orientation }

    mutating func update(isPhoneShaped: Bool, currentContentSize current: CGSize, availableHeight: CGFloat, pictureRatio: CGFloat?, fit: PictureFit = .locked) -> CGSize? {
        defer { wasPhoneShaped = isPhoneShaped; hasSeenAWindow = true }
        guard current.width > 0, current.height > 0 else { return nil }

        if isPhoneShaped, let ratio = pictureRatio, ratio > 0 {
            if !wasPhoneShaped {
                connectSize = hasSeenAWindow ? current : (connectSize ?? Self.defaultConnectSize)
                return phoneSize(height: phoneHeight ?? Self.defaultPhoneHeight, ratio: ratio, availableHeight: availableHeight)
            }
            // Already a phone window: only follow a change of the picture's shape (the phone rotated).
            switch fit {
            case .locked:
                guard abs(current.width / current.height - ratio) > 0.01 else { return nil }
            case .free:
                return nil // a side panel is open, so the picture does not fill the window and its shape means nothing here
            case .orientation:
                guard (current.width > current.height) != (ratio > 1) else { return nil } // only a rotation changes the window's shape
            }
            return phoneSize(height: current.height, ratio: ratio, availableHeight: availableHeight)
        }

        if wasPhoneShaped {
            phoneHeight = current.height
            return connectSize ?? Self.defaultConnectSize
        }
        // Always start at the Connect size, ignoring any frame restored from the last launch.
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

/// Keeps a window fully on screen when it changes size. Pure, so the rules are tested without a window (AppKit coordinates: origin bottom-left).
enum WindowPlacement {
    /// Shrinks the frame to the visible area if it is larger, then slides it the least distance needed to lie inside it.
    static func fitted(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }

    /// A frame of `size` whose top-left corner stays where the old frame's was, then fitted on screen.
    static func resized(_ old: CGRect, to size: CGSize, in visible: CGRect?) -> CGRect {
        let frame = CGRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        return visible.map { fitted(frame, in: $0) } ?? frame
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
