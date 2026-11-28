import AppKit

@MainActor
enum Confirmation {
    struct Answer {
        let confirmed: Bool
        let dontAskAgain: Bool
    }

    static func ask(title: String, message: String, confirm: String, destructive: Bool = false) -> Answer {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .warning : .informational
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don't ask again")
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        return Answer(confirmed: confirmed, dontAskAgain: confirmed && alert.suppressionButton?.state == .on)
    }
}
