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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isAnyRecording else { return .terminateNow }
        Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: await model.prepareToQuit()) }
        return .terminateLater
    }
}
