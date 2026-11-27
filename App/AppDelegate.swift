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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular) // Needed for a bare executable to show a normal window.
        NSApp.activate(ignoringOtherApps: true)
        // The helper windows (Logcat, Mini Mirror, …) mean nothing without the main window, so closing it ends the app.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, Self.isMainWindow(window) else { return }
            NSApp.terminate(nil)
        }
    }

    private var closeObserver: NSObjectProtocol?

    private static let helperWindowIDs = ["logcat", "mini", "apilog", "database"]

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        guard let id = window.identifier?.rawValue, id.contains("AppWindow") else { return false }
        return !helperWindowIDs.contains { id.hasPrefix($0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.restorePhoneChanges()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isAnyRecording else { return .terminateNow }
        Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: await model.prepareToQuit()) }
        return .terminateLater
    }
}
