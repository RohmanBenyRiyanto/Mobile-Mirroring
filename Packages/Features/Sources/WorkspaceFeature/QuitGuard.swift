import AppKit
import Foundation

/// Quitting while a recording is running would leave a broken MP4, so the app asks first and finishes the files properly.
extension AppModel {
    /// True when any phone is being recorded.
    public var isAnyRecording: Bool { sessions.contains { $0.isRecording } }

    /// Stops every recording and waits until the files are complete.
    public func finishRecordings() async {
        for session in sessions where session.isRecording {
            _ = try? await session.scrcpy.stopRecording()
        }
    }

    /// Called when the app is asked to quit. Returns whether it may go ahead: immediately when nothing is recording,
    /// otherwise after the user chooses to stop and save the recordings (or cancels).
    public func prepareToQuit() async -> Bool {
        guard isAnyRecording else { return true }
        guard confirmQuitWhileRecording() else { return false }
        await finishRecordings()
        return true
    }
}

/// The question asked before quitting during a recording. Replaceable in the model, so tests need no dialog.
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
