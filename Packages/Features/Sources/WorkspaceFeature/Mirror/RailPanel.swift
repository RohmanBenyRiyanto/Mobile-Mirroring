import AppKit
import SwiftUI

/// Keeps the control rail in a small borderless panel next to the mirror window. A SwiftUI window cannot hang a
/// capsule outside its own frame, so the rail is a child window: it moves, hides and orders with the mirror window.
/// The panel never takes focus, so the keyboard stays with the phone.
@MainActor
final class RailPanelController: NSObject {
    private let panel: NSPanel
    private let hosting: NSHostingView<AnyView>
    private weak var parent: NSWindow?
    private var observers: [NSObjectProtocol] = []
    /// Space between the window and the rail.
    private static let gap: CGFloat = 12

    init(parent: NSWindow, content: AnyView) {
        self.parent = parent
        hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel = RailPanel(contentRect: CGRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        super.init()
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the rail draws its own
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reposition() }
            })
        }
        // In full screen there is no room beside the window: the rail goes away (it returns with the window).
        observers.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setVisible(false) }
        })
        observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setVisible(true) }
        })
        parent.addChildWindow(panel, ordered: .above)
        reposition()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func setVisible(_ visible: Bool) {
        if visible, parent?.styleMask.contains(.fullScreen) != true {
            if panel.parent == nil { parent?.addChildWindow(panel, ordered: .above) }
            panel.orderFront(nil)
            reposition()
        } else {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    func update(content: AnyView) {
        hosting.rootView = content
        reposition()
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Centered on the window's right edge, kept on the screen.
    private func reposition() {
        guard let parent else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        // The hosted view includes 20 pt of transparent room for the shadow; the visible capsule sits inside it.
        let room: CGFloat = 20
        var origin = CGPoint(x: parent.frame.maxX + Self.gap - room, y: parent.frame.midY - size.height / 2)
        if let visible = (parent.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(origin.x, visible.maxX - size.width + room)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }
}

/// A panel that can be clicked without becoming the key window.
private final class RailPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Puts the rail beside the window this view lives in.
struct RailPanelAttacher: NSViewRepresentable {
    let isVisible: Bool
    let content: AnyView

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        // The window only exists once the view is attached, so continue on the next turn of the run loop.
        DispatchQueue.main.async { [content, isVisible] in
            guard let window = view.window else { return }
            if coordinator.controller == nil {
                coordinator.controller = RailPanelController(parent: window, content: content)
            }
            coordinator.controller?.update(content: content)
            coordinator.controller?.setVisible(isVisible)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        MainActor.assumeIsolated { coordinator.controller?.detach() }
    }

    final class Coordinator {
        var controller: RailPanelController?
    }
}
