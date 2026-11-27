import Foundation
import SwiftUI
import Theme

/// What is being dragged over the mirror, in words: the first file's name and size, and what will happen to it.
public struct DropSummary: Equatable {
    public enum Action: Equatable { case install, import_, copy }

    public let action: Action
    /// "app-debug.apk · 24.6 MB", or "3 files" when several are dragged.
    public let detail: String

    /// Reads the dragged files (their names and sizes only; nothing is opened). Nil when no file is being dragged.
    public static func make(from urls: [URL]) -> DropSummary? {
        let files = urls.filter(\.isFileURL)
        guard let first = files.first else { return nil }
        let action: Action
        switch first.pathExtension.lowercased() {
        case "apk": action = .install
        case KeymapFile.fileExtension: action = .import_
        default: action = .copy
        }
        if files.count > 1 { return DropSummary(action: action, detail: String(localized: "\(files.count) files")) }
        let size = (try? first.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }
        let sizeText = size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        return DropSummary(action: action, detail: [first.lastPathComponent, sizeText].compactMap { $0 }.joined(separator: " · "))
    }
}

/// Over the picture while files are dragged on it: a dark scrim with a blue outline. Solid, not glass (it sits on live video).
struct DropOverlay: View {
    let summary: DropSummary

    private var title: LocalizedStringKey {
        switch summary.action {
        case .install: return "Drop to install"
        case .import_: return "Drop to import the keymap"
        case .copy: return "Drop to copy to the phone"
        }
    }

    var body: some View {
        ZStack {
            Color(red: 8 / 255, green: 10 / 255, blue: 16 / 255).opacity(0.9)
            VStack(spacing: Theme.Space.s2) {
                Text(title).font(Theme.Font.title)
                Text(summary.detail).font(Theme.Font.mono).lineLimit(1).truncationMode(.middle)
                Text("Other files are copied to Download on the phone.").font(Theme.Font.body)
            }
            .foregroundStyle(Theme.OverVideo.text)
            .multilineTextAlignment(.center)
            .padding(Theme.Space.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(red: 74 / 255, green: 155 / 255, blue: 1), lineWidth: 3))
            .padding(Theme.Space.s3)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
