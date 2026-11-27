import AppKit
import Foundation

/// Quitting while a recording is running would leave a broken MP4, so the app asks first and finishes the files properly.
extension AppModel {
    public var isAnyRecording: Bool { sessions.contains { $0.isRecording } }

    public func finishRecordings() async {
        for session in sessions where session.isRecording {
            _ = try? await session.scrcpy.stopRecording()
        }
    }

    /// Returns whether quitting may go ahead. If recordings are running, they are stopped and saved only when the user agrees.
    public func prepareToQuit() async -> Bool {
        guard isAnyRecording else { return true }
        guard confirmQuitWhileRecording() else { return false }
        await finishRecordings()
        return true
    }
}

enum QuitPrompt {
    @MainActor
    static func ask() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "A recording is in progress")
        alert.informativeText = String(localized: "Quitting now would leave the video unfinished. Stop the recording and save it first?")
        alert.addButton(withTitle: String(localized: "Stop Recording and Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
