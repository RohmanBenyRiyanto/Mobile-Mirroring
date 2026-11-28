import AppKit
import SwiftUI
import Theme

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
    public let isMirror: Bool
    public let isFlexible: Bool
    public var host: HostWindow?
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

    @MainActor
    public final class Coordinator {
        var memory = WindowSizeMemory()
        var frameBeforeStreamMode: CGRect?
    }

    public func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            host?.window = window
            window.level = alwaysOnTop ? .floating : .normal
            applyChrome(to: window, coordinator: coordinator)
        }
    }

    @MainActor
    private func applyChrome(to window: NSWindow, coordinator: Coordinator) {
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
        let availableWidth = window.screen?.visibleFrame.width ?? 1600
        let target = coordinator.memory.update(isPhoneShaped: phoneShaped, currentContentSize: current, availableHeight: available, availableWidth: availableWidth, panelWidth: panelWidth,
                                               pictureRatio: phoneShaped ? videoSize.width / videoSize.height : nil, fit: fit)
        if locked {
            window.contentAspectRatio = videoSize
        } else {
            window.resizeIncrements = NSSize(width: 1, height: 1)
        }
        if let target { resize(window, toContent: target) }
        else if panelWidth > 0, isMirror, !isStreamMode, validVideo, !window.styleMask.contains(.fullScreen) {
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

    private func resize(_ window: NSWindow, toContent size: CGSize) {
        let outer = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let frame = WindowPlacement.resized(window.frame, to: outer, in: (window.screen ?? NSScreen.main)?.visibleFrame)
        window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

struct WindowSizeMemory: Equatable {
    static let defaultConnectSize = Theme.Size.connectWindow
    static let defaultPhoneHeight: CGFloat = 818

    private(set) var connectSize: CGSize?
    private(set) var phoneHeight: CGFloat?
    private var wasPhoneShaped = false
    private var lastPanelWidth: CGFloat = 0
    private var hasSeenAWindow = false

    enum PictureFit { case locked, free, orientation }

    mutating func update(isPhoneShaped: Bool, currentContentSize current: CGSize, availableHeight: CGFloat, availableWidth: CGFloat = .infinity, panelWidth: CGFloat = 0, pictureRatio: CGFloat?, fit: PictureFit = .locked) -> CGSize? {
        defer { wasPhoneShaped = isPhoneShaped; hasSeenAWindow = true; lastPanelWidth = panelWidth }
        guard current.width > 0, current.height > 0 else { return nil }

        if isPhoneShaped, let ratio = pictureRatio, ratio > 0 {
            if !wasPhoneShaped {
                connectSize = hasSeenAWindow ? current : (connectSize ?? Self.defaultConnectSize)
                return phoneSize(height: phoneHeight ?? Self.defaultPhoneHeight, ratio: ratio, availableHeight: availableHeight, availableWidth: availableWidth)
            }
            switch fit {
            case .locked:
                guard abs(current.width / current.height - ratio) > 0.01 else { return nil }
            case .free:
                guard panelWidth > 0, panelWidth != lastPanelWidth, current.width > panelWidth else { return nil }
                let height = ((current.width - panelWidth) / ratio).rounded()
                guard abs(height - current.height) > 8 else { return nil }
                return CGSize(width: current.width, height: max(240, min(height, availableHeight - 80)))
            case .orientation:
                guard (current.width > current.height) != (ratio > 1) else { return nil }
            }
            return phoneSize(height: current.height, ratio: ratio, availableHeight: availableHeight, availableWidth: availableWidth)
        }

        if wasPhoneShaped {
            phoneHeight = current.height
            return connectSize ?? Self.defaultConnectSize
        }
        if !hasSeenAWindow, abs(current.width - Self.defaultConnectSize.width) > 1 || abs(current.height - Self.defaultConnectSize.height) > 1 {
            return Self.defaultConnectSize
        }
        return nil
    }

    private func phoneSize(height wanted: CGFloat, ratio: CGFloat, availableHeight: CGFloat, availableWidth: CGFloat = .infinity) -> CGSize {
        let height = max(240, min(wanted, availableHeight - 80, (availableWidth - 24) / ratio))
        return CGSize(width: (height * ratio).rounded(), height: height.rounded())
    }
}

enum WindowPlacement {
    static func fitted(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }

    static func resized(_ old: CGRect, to size: CGSize, in visible: CGRect?) -> CGRect {
        let frame = CGRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        return visible.map { fitted(frame, in: $0) } ?? frame
    }
}

public enum StreamWindow {
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
