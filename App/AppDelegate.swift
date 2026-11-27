import AppKit
import WorkspaceFeature

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keymap files opened from Finder arrive here and wait until the window model can import them.
    let fileInbox = FileOpenInbox()

    func application(_ application: NSApplication, open urls: [URL]) {
        fileInbox.receive(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular) // lets a bare executable show a normal window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
