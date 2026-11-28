import AppKit

@MainActor
final class RecordingStatusItem {
    private var item: NSStatusItem?
    private var timer: Timer?
    private var startedAt: Date?
    private var stop: () -> Void = {}
    private var show: () -> Void = {}

    static func shouldShow(isStreamMode: Bool, isRecording: Bool) -> Bool { isStreamMode && isRecording }

    static func title(elapsed: TimeInterval) -> String { "● " + RecordingPill.clock(elapsed) }

    func update(visible: Bool, startedAt: Date?, stop: @escaping () -> Void, show: @escaping () -> Void) {
        self.stop = stop
        self.show = show
        guard visible, let startedAt else { remove(); return }
        guard item == nil || self.startedAt != startedAt else { return }
        self.startedAt = startedAt
        let item = self.item ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Stop Recording"), action: #selector(stopRecording), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Show Controls"), action: #selector(showControls), keyEquivalent: "").target = self
        item.menu = menu
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        guard let startedAt, let button = item?.button else { return }
        let text = NSMutableAttributedString(string: Self.title(elapsed: Date().timeIntervalSince(startedAt)),
                                             attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
        text.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 0, length: 1))
        button.attributedTitle = text
    }

    private func remove() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    @objc private func stopRecording() { stop() }
    @objc private func showControls() { show() }
}
