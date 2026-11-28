import AppKit
import WorkspaceFeature

final class AppDelegate: NSObject, NSApplicationDelegate {
    let fileInbox = FileOpenInbox()
    weak var model: AppModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        fileInbox.receive(urls)
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleTerminationSignals()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if !NSApp.windows.contains(where: { $0.isVisible && Self.isMainWindow($0) }) {
                NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                for window in NSApp.windows where Self.helperWindowIDs.contains(window.identifier?.rawValue ?? "") { window.close() }
                self.isSettlingAtLaunch = false
            }
        }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            guard let window = note.object as? NSWindow, Self.isMainWindow(window) else { return }
            if self.model?.quitsWhenWindowCloses ?? false { NSApp.terminate(nil); return }
            self.model?.windowClosed()
            for helper in NSApp.windows where Self.helperWindowIDs.contains(helper.identifier?.rawValue ?? "") { helper.close() }
        }
    }

    private var closeObserver: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []

    private func handleTerminationSignals() {
        for number in [SIGTERM, SIGHUP, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
    private var isSettlingAtLaunch = true

    private static let helperWindowIDs = ["logcat", "mini", "apilog", "database"]

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.styleMask.contains(.titled), window.level == .normal, window.contentViewController != nil || window.contentView != nil else { return false }
        let id = window.identifier?.rawValue ?? ""
        return !helperWindowIDs.contains(id) && !id.localizedCaseInsensitiveContains("settings") && !(window is NSPanel)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.restorePhoneChanges()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !isSettlingAtLaunch && (model?.quitsWhenWindowCloses ?? false) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !NSApp.windows.contains(where: { $0.isVisible && Self.isMainWindow($0) }) {
            NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isAnyRecording else { return .terminateNow }
        Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: await model.prepareToQuit()) }
        return .terminateLater
    }
}
