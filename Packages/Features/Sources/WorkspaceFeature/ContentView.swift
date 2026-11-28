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

    /// The window's width with no panel open, remembered while any panel is open so closing them returns to exactly that.
    @State private var widthWithoutPanels: CGFloat?
    @State private var host = HostWindow()

    private var openPanelWidth: CGFloat {
        (model.showsPerformance ? PerformancePanel.width : 0) + (model.showsQuickToggles ? QuickTogglesPanel.width : 0)
            + (model.showsInspectorPanel ? InspectorPanel.width : 0)
    }

    /// Gives the window the width of the picture plus every open panel, so panels sit beside the picture instead of covering it.
    /// It grows to the right; if the screen has no room there, the window slides left just enough to stay fully visible.
    @MainActor private func syncWindowToPanels() {
        guard let window = host.window else { return }
        if openPanelWidth > 0, widthWithoutPanels == nil { widthWithoutPanels = window.frame.width }
        let base = widthWithoutPanels ?? window.frame.width
        if openPanelWidth == 0 { widthWithoutPanels = nil }
        // A locked aspect ratio would refuse the new frame, so it is released first; the styler locks it again once the state settles.
        window.resizeIncrements = NSSize(width: 1, height: 1)
        var frame = window.frame
        frame.size.width = max(base + openPanelWidth, window.minSize.width)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame { frame = WindowPlacement.fitted(frame, in: visible) }
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
                                 locksAspect: isMirrorWindow && model.editor == nil && !model.showsPerformance && !model.showsQuickToggles && !model.showsInspectorPanel,
                                 isMirror: isMirrorWindow, isFlexible: model.active?.usesVirtualDisplay == true, host: host))
        .overlay(alignment: .bottom) { NoticeToast().animated(value: model.notice) }
        .animated(value: isMirrorWindow)
        .animated(value: model.showsPerformance)
        .animated(value: model.showsQuickToggles)
        .animated(value: model.showsInspectorPanel)
        .onChange(of: model.showsInspectorPanel) { _, _ in syncWindowToPanels() }
        .onChange(of: model.showsQuickToggles) { _, _ in syncWindowToPanels() }
        .onChange(of: model.showsPerformance) { _, _ in syncWindowToPanels() }
        .sheet(isPresented: $model.showsDeviceInfo) { DeviceInfoSheet() }
        .sheet(isPresented: Binding(get: { model.lostConnection != nil }, set: { if !$0 { model.dismissLostConnection() } })) { ConnectionLostSheet().environmentObject(model) }
        .sheet(isPresented: $model.showsOnboarding) { OnboardingView().environmentObject(model) }
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
            if (model.sessions.count > 1 || model.devices.contains { $0.state == .offline && !model.sessions.map(\.serial).contains($0.serial) } && !model.sessions.isEmpty) && !model.isStreamMode { PhoneTabs() }
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
            MirrorView(session: session, keymap: keymap, inspector: inspector, design: design, videoSize: model.videoSize, flexibleDisplay: model.active?.usesVirtualDisplay == true,
                       maxDisplayEdge: VirtualDisplayMath.longestEdge(forMaxSize: model.active?.settings.quality.maxSize ?? 0),
                       initialLandscape: model.active?.settings.virtualDisplay.initialLandscape ?? false,
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
            if model.showsInspectorPanel {
                InspectorPanel(inspector: inspector, densityScale: model.deviceInfo?.densityScale).transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if model.showsQuickToggles, let session = model.active {
                QuickTogglesPanel(tools: session.developerTools, traffic: session.traffic).transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if let editor = model.editor {
                KeymapEditorPanel(editor: editor, foreground: model.foreground, message: model.editorMessage, apps: model.appPickerItems, isLoadingApps: model.isLoadingApps, loadApps: { await model.loadInstalledApps() },
                                  onSave: { _ = model.saveEditor() }, onClose: { model.closeEditor(save: $0) })
            }
        }
    }
}

struct PhoneTab: Equatable, Identifiable {
    let id: String
    let title: String
    let isActive: Bool
    let isRecording: Bool
    let isOffline: Bool

    /// One tab per mirrored phone, then a dimmed tab for each known phone that is not responding.
    static func tabs(mirrored: [(serial: String, name: String, isRecording: Bool)], devices: [AndroidDevice], activeSerial: String?) -> [PhoneTab] {
        let live = mirrored.map {
            PhoneTab(id: $0.serial, title: $0.name.isEmpty ? $0.serial : $0.name, isActive: $0.serial == activeSerial, isRecording: $0.isRecording, isOffline: false)
        }
        let known = Set(mirrored.map(\.serial))
        let offline = devices.filter { !known.contains($0.serial) && ($0.state == .offline || $0.state == .unauthorized) }
            .map { PhoneTab(id: $0.serial, title: $0.title, isActive: false, isRecording: false, isOffline: true) }
        return live + offline
    }
}

private struct PhoneTabs: View {
    @EnvironmentObject private var model: AppModel

    private var tabs: [PhoneTab] {
        PhoneTab.tabs(mirrored: model.sessions.map { ($0.serial, $0.deviceName, $0.isRecording) }, devices: model.devices, activeSerial: model.activeSerial)
    }

    var body: some View {
        HStack(spacing: Theme.Space.s1) {
            ForEach(tabs) { tab in
                Button { tab.isOffline ? model.reconnectDevices() : model.activate(tab.id) } label: {
                    HStack(spacing: Theme.Space.s1) {
                        if tab.isRecording { Circle().fill(Theme.Palette.red.color).frame(width: 7, height: 7).accessibilityLabel("Recording") }
                        Text(verbatim: tab.title).lineLimit(1)
                        if tab.isOffline { Text("Offline").font(Theme.Font.caption) }
                    }
                    .padding(.horizontal, Theme.Space.s3).padding(.vertical, 4)
                    .background(tab.isActive ? Theme.Palette.control.color : .clear, in: Capsule())
                    .foregroundStyle(tab.isActive ? .primary : .secondary)
                    .opacity(tab.isOffline ? 0.6 : 1)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.s3)
        .padding(.vertical, Theme.Space.s2)
        .background(.bar)
    }
}

private struct StatsOverlay: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var foreground: ForegroundAppDetector

    init(foreground: ForegroundAppDetector) { self.foreground = foreground }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.0f fps  ·  %.1f Mbps  ·  %.1f ms jitter", model.stats.framesPerSecond, model.stats.megabitsPerSecond, model.stats.jitterMillis))
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


private struct ConnectionLostSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let lost = model.lostConnection {
            VStack(spacing: Theme.Space.s4) {
                Image(systemName: "bolt.horizontal.circle").font(.system(size: 32)).foregroundStyle(.secondary)
                Text("Connection lost").font(Theme.Font.title)
                Text("\(lost.name) stopped responding.").foregroundStyle(.secondary)
                Text(verbatim: lost.reason).font(Theme.Font.monoCaption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                if lost.isGivingUp {
                    Text("Could not reconnect. Check the cable and that the phone is unlocked.").multilineTextAlignment(.center)
                } else {
                    HStack(spacing: Theme.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Reconnecting, attempt \(lost.attempt) of \(ReconnectPolicy.maxAttempts)").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Close") { model.dismissLostConnection() }.keyboardShortcut(.cancelAction).secondaryAction()
                    Button("Try Now") { model.retryNow() }.prominentAction().keyboardShortcut(.defaultAction)
                }
            }
            .padding(Theme.Space.s6)
            .frame(width: 420)
        }
    }
}
