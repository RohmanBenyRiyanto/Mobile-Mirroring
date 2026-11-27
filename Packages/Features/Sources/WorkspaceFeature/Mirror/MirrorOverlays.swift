import AppKit
import SwiftUI
import Theme

/// A glass notice that can offer to show a saved file.
struct ToastView: View {
    let text: String
    var file: URL?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s2) {
            Text(text).font(Theme.Font.body).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let file {
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    .buttonStyle(.plain)
                    .font(Theme.Font.body.weight(.medium))
                    .foregroundStyle(Theme.Palette.accentText.color)
                    .padding(.horizontal, Theme.Space.s3)
                    .frame(height: 24)
            }
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24) }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
        }
        .padding(.leading, Theme.Space.s3)
        .padding(.trailing, Theme.Space.s2)
        .padding(.vertical, Theme.Space.s2)
        .frame(maxWidth: 480)
        .glassSurface(in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        .padding(.horizontal, Theme.Space.s3)
        .padding(.bottom, 32)
    }
}

struct NoticeToast: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let notice = model.notice {
            ToastView(text: notice, file: model.noticeFile) { model.notice = nil }
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(4))
                    model.notice = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Solid scrim rather than glass, since glass over live video costs GPU time.
struct RecordingPill: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            HStack(spacing: Theme.Space.s2) {
                Circle().fill(Theme.Palette.redFill.color).frame(width: 8, height: 8)
                Text(Self.clock(context.date.timeIntervalSince(startedAt))).font(Theme.Font.monoCaption)
            }
            .padding(.horizontal, Theme.Space.s3)
            .frame(height: 24)
            .overVideo(in: Capsule())
            .padding(.top, Theme.Space.s3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording")
            .accessibilityValue(Self.clock(context.date.timeIntervalSince(startedAt)))
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

struct StreamHint: View {
    var body: some View {
        HStack(spacing: Theme.Space.s2) {
            Text("Press")
            Text(verbatim: "⇧⌘B").font(Theme.Font.mono)
            Text("or Esc to show controls")
        }
        .font(Theme.Font.body)
        .padding(.horizontal, Theme.Space.s4)
        .frame(height: 32)
        .overVideo(in: Capsule())
        .padding(.bottom, Theme.Space.s8)
        .allowsHitTesting(false)
    }
}
