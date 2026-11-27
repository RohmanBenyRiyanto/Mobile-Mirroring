import AppKit
import Components
import SwiftUI
import DomainModels
import InspectorFeature
import KeymapFeature
import Networking
import Theme

public struct ContentView: View {

    public init() {

    }
    @EnvironmentObject private var model: AppModel

    /// Grows or shrinks the window by the docked panel's width, keeping its top-left corner still.
    @MainActor private static func resizeWindow(byWidth delta: CGFloat) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        var frame = window.frame
        frame.size.width = max(frame.width + delta, window.minSize.width)
        window.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private var isMirrorWindow: Bool { model.isMirroring && !model.isAddingDevice }

    public var body: some View {
        Group {
            if isMirrorWindow, let phone = model.active {
                MirrorScreen(session: phone.scrcpy, keymap: phone.keymap, inspector: phone.inspector, design: phone.design)
                    .transition(.opacity)
            } else {
                ConnectScreen()
                    .transition(.opacity)
            }
        }
        .frame(minWidth: isMirrorWindow ? 200 : Theme.Size.connectMinimum.width,
               minHeight: isMirrorWindow ? 360 : Theme.Size.connectMinimum.height)
        .background(WindowStyler(isStreamMode: model.isStreamMode, alwaysOnTop: model.alwaysOnTop, videoSize: model.videoSize,
                                 locksAspect: isMirrorWindow && model.editor == nil && !model.showsPerformance))
        .overlay(alignment: .bottom) { NoticeToast().animated(value: model.notice) }
        .animated(value: isMirrorWindow)
        .animated(value: model.showsPerformance)
        .onChange(of: model.showsPerformance) { _, on in Self.resizeWindow(byWidth: on ? PerformancePanel.width : -PerformancePanel.width) }
        .sheet(isPresented: $model.showsDeviceInfo) { DeviceInfoSheet() }
    }
}

// MARK: - Mirroring

private struct MirrorScreen: View {
    @EnvironmentObject private var model: AppModel
    let session: ScrcpySession
    let keymap: KeymapController
    let inspector: InspectorModel
    let design: DesignModel
    @State private var dropSummary: DropSummary?
    @State private var showsStreamHint = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            if model.sessions.count > 1 && !model.isStreamMode { PhoneTabs() }
            content
        }
        .navigationTitle(model.deviceName)
        .background(RailPanelAttacher(isVisible: !model.isStreamMode && model.editor == nil,
                                      content: AnyView(RailView(model: model, isCollapsed: $model.isRailCollapsed,
                                                                openLogcat: { openWindow(id: "logcat") },
                                                                customize: { model.showSettingsPane("rail"); openSettings() }).themed(model.appearance))))
        .overlay(alignment: .bottom) { if showsStreamHint { StreamHint().transition(.opacity.combined(with: .move(edge: .bottom))) } }
        .onChange(of: model.isStreamMode) { _, on in
            guard on else { showsStreamHint = false; return }
            withAnimation(Theme.Motion.smooth) { showsStreamHint = true }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(Theme.Motion.smooth) { showsStreamHint = false }
            }
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            MirrorView(session: session, keymap: keymap, inspector: inspector, design: design, videoSize: model.videoSize,
                       onDrag: { dropSummary = $0 }, onDrop: { model.handleDrop($0) }, onEscape: { model.handleEscape() },
                       isStreamMode: { model.isStreamMode }, onExitStreamMode: { model.isStreamMode = false })
                .aspectRatio(model.videoSize, contentMode: .fit)
                .overlay(alignment: .topLeading) { if model.showsStats { StatsOverlay(foreground: model.foreground) } }
                .overlay(alignment: .top) {
                    if let started = model.recordingStartedAt, !model.isStreamMode { RecordingPill(startedAt: started).transition(.opacity.combined(with: .move(edge: .top))) }
                }
                .animated(value: model.recordingStartedAt != nil)
                .animated(value: dropSummary)
                .overlay {
                    if design.grid != .off || design.tool != .off {
                        DesignOverlay(design: design, videoSize: model.videoSize,
                                      screenSize: model.deviceInfo?.screenSize(matching: model.videoSize) ?? model.videoSize,
                                      densityScale: model.deviceInfo?.densityScale)
                    }
                }
                .overlay { if inspector.isOn { InspectorOverlay(inspector: inspector, videoSize: model.videoSize, densityScale: model.deviceInfo?.densityScale) } }
                .overlay { if let editor = model.editor { KeymapEditorOverlay(editor: editor, videoSize: model.videoSize) } }
                .overlay { if let summary = dropSummary { DropOverlay(summary: summary) } }
            if model.showsPerformance, let session = model.active {
                PerformancePanel(monitor: session.performance).transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if let editor = model.editor {
                KeymapEditorPanel(editor: editor, foreground: model.foreground, message: model.editorMessage,
                                  onSave: { _ = model.saveEditor() }, onClose: { model.closeEditor(save: $0) })
            }
        }
    }
}

private struct PhoneTabs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.sessions, id: \.serial) { session in
                Button(session.deviceName.isEmpty ? session.serial : session.deviceName) { model.activate(session.serial) }
                    .buttonStyle(.borderless)
                    .fontWeight(session.serial == model.activeSerial ? .medium : .regular)
                    .foregroundStyle(session.serial == model.activeSerial ? .primary : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct StatsOverlay: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var foreground: ForegroundAppDetector

    init(foreground: ForegroundAppDetector) { self.foreground = foreground }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.0f fps  ·  %.1f Mbps", model.stats.framesPerSecond, model.stats.megabitsPerSecond))
            Text("\(Int(model.videoSize.width))×\(Int(model.videoSize.height))  ·  \(model.settings.quality.codec.rawValue.uppercased())")
            if let info = model.deviceInfo { Text("\(info.density) dpi  ·  Android \(info.androidRelease)") }
            if let app = foreground.current { Text(app.package).lineLimit(1) }
            if model.streamURL != nil {
                Text("OBS viewers: \(model.streamViewerCount)")
            }
        }
        .font(Theme.Font.monoCaption.weight(.medium))
        .padding(Theme.Space.s2)
        .overVideo(in: RoundedRectangle(cornerRadius: Theme.Radius.field))
        .padding(Theme.Space.s2)
        .allowsHitTesting(false)
    }
}
