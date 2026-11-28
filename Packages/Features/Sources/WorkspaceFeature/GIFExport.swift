import AppKit
import Foundation
import Media
import UniformTypeIdentifiers

extension AppModel {
    public func exportRecordingAsGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.message = String(localized: "Choose a recording to turn into a GIF")
        panel.directoryURL = settings.recordingFolder.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.appendingPathComponent(AppInfo.name, isDirectory: true)
        guard panel.runModal() == .OK, let video = panel.url, let options = Self.askForRange() else { return }

        let target = video.deletingPathExtension().appendingPathExtension("gif")
        notice = String(localized: "Making a GIF")
        Task {
            do {
                try await GIFExporter.export(video: video, to: target, options: options)
                noticeFile = target
                notice = String(localized: "Saved \(target.lastPathComponent)")
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    private static func askForRange() -> GIFExporter.Options? {
        let start = NSTextField(string: "0"), length = NSTextField(string: "10")
        for field in [start, length] { field.alignment = .right; field.frame.size = NSSize(width: 70, height: 22) }
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "Start (seconds)")), start],
            [NSTextField(labelWithString: String(localized: "Length (seconds, up to 30)")), length],
        ])
        grid.frame.size = NSSize(width: 280, height: 56)
        let alert = NSAlert()
        alert.messageText = String(localized: "Which part should become a GIF?")
        alert.informativeText = String(localized: "GIFs are small and short. The picture is shrunk to fit.")
        alert.accessoryView = grid
        alert.addButton(withTitle: String(localized: "Make GIF"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return GIFExporter.Options(start: Double(start.stringValue) ?? 0, length: Double(length.stringValue) ?? 10)
    }
}
