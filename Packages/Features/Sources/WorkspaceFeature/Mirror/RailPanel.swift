import AppKit
import SwiftUI

/// Hosts the rail in a borderless child panel, since a SwiftUI window cannot draw outside its own frame.
/// The panel never takes focus, so the keyboard stays with the phone.
@MainActor
final class RailPanelController: NSObject {
    private let panel: NSPanel
    private let hosting: NSHostingView<AnyView>
    private weak var parent: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private let tooltips = RailTooltipPresenter()
    private static let gap: CGFloat = 12

    init(parent: NSWindow, content: AnyView) {
        self.parent = parent
        hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel = RailPanel(contentRect: CGRect(origin: .zero, size: hosting.fittingSize), styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        super.init()
        panel.contentView = hosting
        hosting.rootView = AnyView(content.environment(\.railTooltip, RailTooltipAction(show: { [weak self] tip, frame in self?.showTooltip(tip, frame) })))
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
        // The rail belongs to the phone window: it goes into the Dock with it and comes back with it.
        observers.append(center.addObserver(forName: NSWindow.didMiniaturizeNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setVisible(false) }
        })
        observers.append(center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setVisible(true) }
        })
        parent.addChildWindow(panel, ordered: .above)
        reposition()
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func setVisible(_ visible: Bool) {
        if visible, parent?.styleMask.contains(.fullScreen) != true, parent?.isMiniaturized != true {
            if panel.parent == nil { parent?.addChildWindow(panel, ordered: .above) }
            panel.orderFront(nil)
            reposition()
        } else {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    func update(content: AnyView) {
        hosting.rootView = AnyView(content.environment(\.railTooltip, RailTooltipAction(show: { [weak self] tip, frame in self?.showTooltip(tip, frame) })))
        reposition()
    }

    /// `frame` is the hovered button in the rail view's coordinates (origin top-left); the bubble opens to its left.
    private func showTooltip(_ content: RailTooltipContent?, _ frame: CGRect) {
        guard let content, frame != .zero else { tooltips.hide(); return }
        let panelFrame = panel.frame
        let screenRect = CGRect(x: panelFrame.minX + frame.minX, y: panelFrame.maxY - frame.maxY, width: frame.width, height: frame.height)
        tooltips.show(content, besideButtonAt: screenRect, parent: parent)
    }

    func detach() {
        tooltips.hide()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

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

/// A small bubble in its own panel, so it can sit outside the rail's frame. It never takes the mouse or the keyboard.
@MainActor
final class RailTooltipPresenter {
    private var panel: NSPanel?
    private var pending: Task<Void, Never>?
    private var isShowing = false

    func show(_ content: RailTooltipContent, besideButtonAt button: CGRect, parent: NSWindow?) {
        pending?.cancel()
        // The first tooltip waits a moment so moving across the rail does not flash bubbles; moving between buttons is instant.
        let delay: Duration = isShowing ? .milliseconds(0) : .milliseconds(450)
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            present(content, button: button, parent: parent)
        }
    }

    func hide() {
        pending?.cancel()
        pending = nil
        isShowing = false
        panel?.orderOut(nil)
    }

    private func present(_ content: RailTooltipContent, button: CGRect, parent: NSWindow?) {
        let hosting = NSHostingView(rootView: RailTooltipBubble(content: content))
        let size = hosting.fittingSize
        let panel = self.panel ?? {
            let new = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            new.isOpaque = false
            new.backgroundColor = .clear
            new.hasShadow = false
            new.ignoresMouseEvents = true
            new.isReleasedWhenClosed = false
            new.level = .floating
            new.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
            return new
        }()
        self.panel = panel
        panel.contentView = hosting
        // The rail's own padding (20 pt of shadow room) sits left of the button, so the bubble keeps a little extra distance.
        var origin = CGPoint(x: button.minX - size.width - 18, y: button.midY - size.height / 2)
        if let visible = (parent?.screen ?? NSScreen.main)?.visibleFrame { origin.x = max(origin.x, visible.minX + 8) }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)
        isShowing = true
    }
}

private struct RailTooltipBubble: View {
    let content: RailTooltipContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(verbatim: content.title).font(.system(size: 12, weight: .semibold))
                if let shortcut = content.shortcut {
                    Text(verbatim: shortcut).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            if let detail = content.detail { Text(verbatim: detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: 240, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .padding(10)
    }
}

/// A panel that can be clicked without becoming the key window.
private final class RailPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

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
