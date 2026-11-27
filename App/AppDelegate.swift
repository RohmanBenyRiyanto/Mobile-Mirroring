import AppKit
import WorkspaceFeature

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keymap files opened from Finder arrive here and wait until the window model can import them.
    let fileInbox = FileOpenInbox()
    /// Set by the app once its model exists; quitting asks it first (a recording must be finished properly).
    weak var model: AppModel?

    func application(_ application: NSApplication, open urls: [URL]) {
        fileInbox.receive(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular) // lets a bare executable show a normal window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isAnyRecording else { return .terminateNow }
        Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: await model.prepareToQuit()) }
        return .terminateLater
    }
}
