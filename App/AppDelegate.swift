import AppKit
import WorkspaceFeature

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Holds Finder-opened files until the window model can import them.
    let fileInbox = FileOpenInbox()
    /// Set once the model exists; quitting asks it first so a recording can finish.
    weak var model: AppModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        fileInbox.receive(urls)
    }

    /// The app ends when its main window closes, so macOS would otherwise save "no windows" and open nothing next time.
    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleTerminationSignals()
        NSApp.setActivationPolicy(.regular) // Needed for a bare executable to show a normal window.
        NSApp.activate(ignoringOtherApps: true)
        // The system can reopen helper windows without the phone window. Make sure the phone window exists, then put the helpers away
        // so a launch starts clean. Quitting on "last window closed" waits until this has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if !NSApp.windows.contains(where: { $0.isVisible && Self.isMainWindow($0) }) {
                NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                for window in NSApp.windows where Self.helperWindowIDs.contains(window.identifier?.rawValue ?? "") { window.close() }
                self.isSettlingAtLaunch = false
            }
        }
        // The helper windows (Logcat, Mini Mirror, …) mean nothing without the main window, so closing it ends the app.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, Self.isMainWindow(window) else { return }
            NSApp.terminate(nil)
        }
    }

    private var closeObserver: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []

    /// A plain `kill` (or a log-out) ends the app without its usual goodbye; route it through a normal quit so phone settings are put back.
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

    /// The phone window is the only normal titled window that is not a helper or the Settings window.
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        guard window.styleMask.contains(.titled), window.level == .normal, window.contentViewController != nil || window.contentView != nil else { return false }
        let id = window.identifier?.rawValue ?? ""
        return !helperWindowIDs.contains(id) && !id.localizedCaseInsensitiveContains("settings") && !(window is NSPanel)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.restorePhoneChanges()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !isSettlingAtLaunch }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isAnyRecording else { return .terminateNow }
        Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: await model.prepareToQuit()) }
        return .terminateLater
    }
}
