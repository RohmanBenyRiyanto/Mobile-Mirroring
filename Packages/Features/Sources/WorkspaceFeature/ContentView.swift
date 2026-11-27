import SwiftUI
import DomainModels
import InspectorFeature
import KeymapFeature
import Networking

public struct ContentView: View {

    public init() {

    }
    @EnvironmentObject private var model: AppModel

    public var body: some View {
        Group {
            if model.isMirroring, !model.isAddingDevice, let phone = model.active {
                MirrorScreen(session: phone.scrcpy, keymap: phone.keymap, inspector: phone.inspector, design: phone.design)
            } else {
                ConnectScreen()
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .background(WindowStyler(isStreamMode: model.isStreamMode, alwaysOnTop: model.alwaysOnTop, videoSize: model.videoSize))
        .overlay(alignment: .bottom) { NoticeBanner() }
    }
}

// MARK: - Mirroring

/// The live phone screen, with a control rail unless stream mode hides it.
private struct MirrorScreen: View {
    @EnvironmentObject private var model: AppModel
    let session: ScrcpySession
    let keymap: KeymapController
    let inspector: InspectorModel
    let design: DesignModel

    var body: some View {
        VStack(spacing: 0) {
            if model.sessions.count > 1 && !model.isStreamMode { PhoneTabs() }
            content
        }
        .navigationTitle(model.deviceName)
    }

    private var content: some View {
        HStack(spacing: 0) {
            MirrorView(session: session, keymap: keymap, inspector: inspector, design: design, videoSize: model.videoSize)
                .aspectRatio(model.videoSize, contentMode: .fit)
                .overlay(alignment: .topLeading) { if model.showsStats { StatsOverlay(foreground: model.foreground) } }
                .overlay {
                    if design.grid != .off || design.tool != .off {
                        DesignOverlay(design: design, videoSize: model.videoSize,
                                      screenSize: model.deviceInfo?.screenSize(matching: model.videoSize) ?? model.videoSize,
                                      densityScale: model.deviceInfo?.densityScale)
                    }
                }
                .overlay { if inspector.isOn { InspectorOverlay(inspector: inspector, videoSize: model.videoSize, densityScale: model.deviceInfo?.densityScale) } }
                .overlay { if let editor = model.editor { KeymapEditorOverlay(editor: editor, videoSize: model.videoSize) } }
                .dropDestination(for: URL.self) { urls, _ in
                    model.handleDrop(urls)
                    return true
                }
            if let editor = model.editor {
                KeymapEditorPanel(editor: editor, foreground: model.foreground, message: model.editorMessage,
                                  onSave: { _ = model.saveEditor() }, onClose: { model.closeEditor(save: $0) })
            } else if !model.isStreamMode {
                ControlRail()
            }
        }
    }
}

/// Switches between the phones that are being mirrored.
private struct PhoneTabs: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.sessions, id: \.serial) { session in
                Button(session.deviceName.isEmpty ? session.serial : session.deviceName) { model.activate(session.serial) }
                    .buttonStyle(.borderless)
                    .fontWeight(session.serial == model.activeSerial ? .semibold : .regular)
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
                Text("OBS: \(model.streamViewerCount) viewer\(model.streamViewerCount == 1 ? "" : "s")")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
        .allowsHitTesting(false)
    }
}

private struct ControlRail: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            RailButton("Back", "chevron.backward") { model.press(.back) }
            RailButton("Home", "circle") { model.press(.home) }
            RailButton("Recents", "square") { model.press(.appSwitch) }
            Divider()
            RailButton("Volume up", "speaker.plus") { model.press(.volumeUp) }
            RailButton("Volume down", "speaker.minus") { model.press(.volumeDown) }
            RailButton("Power", "power") { model.press(.power) }
            Divider()
            RailButton("Notifications", "bell") { model.send(.expandNotificationPanel) }
            RailButton("Quick settings", "slider.horizontal.3") { model.send(.expandSettingsPanel) }
            RailButton("Rotate", "rotate.right") { model.send(.rotateDevice) }
            Divider()
            RailButton("Screenshot", "camera") { model.takeScreenshot() }
            RailButton(model.isRecording ? "Stop recording" : "Record screen",
                       model.isRecording ? "stop.circle.fill" : "record.circle",
                       tint: model.isRecording ? .red : nil) { model.toggleRecording() }
            RailButton(model.isMuted ? "Unmute" : "Mute", model.isMuted ? "speaker.slash" : "speaker.wave.2") { model.toggleMute() }
            Divider()
            RailButton("Stream mode (clean window for OBS)", "rectangle.on.rectangle") { model.isStreamMode = true }
            RailButton("Statistics", "chart.xyaxis.line", tint: model.showsStats ? .accentColor : nil) { model.showsStats.toggle() }
            Spacer()
            RailButton("Add another phone", "plus.circle") { model.isAddingDevice = true }
            RailButton("Disconnect", "xmark.circle") { model.disconnect() }
        }
        .padding(10)
        .frame(width: 52)
        .background(.bar)
    }
}

private struct RailButton: View {
    let title: String
    let symbol: String
    let tint: Color?
    let action: () -> Void

    init(_ title: String, _ symbol: String, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 24) }
            .buttonStyle(.borderless)
            .foregroundStyle(tint ?? .primary)
            .help(title)
            .accessibilityLabel(title)
    }
}

// MARK: - Connect and settings

private struct ConnectScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            DeviceSection()
            WirelessSection()
            QualitySection(settings: $model.settings)
            OBSSection(settings: $model.settings)
            BehaviorSection(settings: $model.settings)

            Section {
                if case let .failed(message) = model.state {
                    Text(message).foregroundStyle(.red).textSelection(.enabled)
                }
                Button(model.state == .connecting ? "Connecting…" : "Start Mirroring") { model.connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.state == .connecting || model.selectedDevice?.isReady != true)
                if !model.sessions.isEmpty {
                    Button("Back to mirror") { model.isAddingDevice = false }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DeviceSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section("Device") {
            if model.isAdbMissing {
                Label(ADBError.notFound.localizedDescription, systemImage: "exclamationmark.triangle")
            } else if model.devices.isEmpty {
                Label("Connect your phone with USB and enable USB debugging.", systemImage: "cable.connector")
            } else {
                Picker("Phone", selection: $model.selectedSerial) {
                    ForEach(model.devices) { device in
                        Text(device.isReady ? device.title : "\(device.title) (\(device.state.rawValue))")
                            .tag(Optional(device.serial))
                    }
                }
            }
        }
    }
}

private struct WirelessSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var pairAddress = ""
    @State private var pairCode = ""
    @State private var connectAddress = ""

    var body: some View {
        Section {
            DisclosureGroup("Wireless") {
                Button("Switch the connected phone to Wi-Fi") { model.switchToWireless() }
                    .disabled(model.selectedDevice?.isReady != true || model.selectedSerial?.contains(":") == true)

                LabeledContent("Pair (Android 11+)") {
                    TextField("host:port", text: $pairAddress).frame(width: 150)
                    SecureField("code", text: $pairCode).frame(width: 70)
                    Button("Pair") {
                        model.pair(address: pairAddress, code: pairCode)
                        pairCode = ""
                    }
                    .disabled(!WirelessInput.isValidAddress(pairAddress) || !WirelessInput.isValidPairingCode(pairCode))
                }
                LabeledContent("Connect") {
                    TextField("host:port", text: $connectAddress).frame(width: 150)
                    Button("Connect") { model.connectWireless(address: connectAddress) }
                        .disabled(!WirelessInput.isValidAddress(connectAddress))
                }
            }
        }
    }
}

private struct QualitySection: View {
    @Binding var settings: MirrorSettings

    private var preset: Binding<QualityPreset> {
        Binding(get: { settings.quality.matchingPreset },
                set: { if let values = VideoQuality.values(for: $0) { settings.quality = values } })
    }

    var body: some View {
        Section("Quality") {
            Picker("Preset", selection: preset) {
                ForEach(QualityPreset.allCases) { Text($0.title).tag($0) }
            }
            Text(settings.quality.matchingPreset.summary).font(.caption).foregroundStyle(.secondary)

            DisclosureGroup("Advanced") {
                Picker("Codec", selection: $settings.quality.codec) {
                    ForEach(VideoCodec.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Max resolution: \(settings.quality.maxSize == 0 ? "native" : "\(settings.quality.maxSize) px")",
                        value: $settings.quality.maxSize, in: VideoQuality.maxSizeRange, step: 320)
                Stepper("Bitrate: \(settings.quality.bitRateMbps) Mbps", value: $settings.quality.bitRateMbps, in: VideoQuality.bitRateRange)
                Stepper("Frame rate: \(settings.quality.maxFPS) fps", value: $settings.quality.maxFPS, in: VideoQuality.frameRateRange, step: 15)
                Stepper("Key frame every \(settings.quality.keyFrameIntervalSeconds) s",
                        value: $settings.quality.keyFrameIntervalSeconds, in: VideoQuality.keyFrameIntervalRange)
                Toggle("Constant bitrate", isOn: $settings.quality.constantBitRate)
            }
        }
    }
}

private struct OBSSection: View {
    @Binding var settings: MirrorSettings

    var body: some View {
        Section("OBS") {
            Toggle("Stream to OBS (local, no re-encoding)", isOn: $settings.obsStreamEnabled)
            if settings.obsStreamEnabled {
                Stepper("Port: \(settings.obsStreamPort)", value: $settings.obsStreamPort, in: MirrorSettings.streamPortRange)
                Text("In OBS: add a Media Source, untick Local File, set Input to http://127.0.0.1:\(settings.obsStreamPort)/live.ts and Input Format to mpegts. Set Network Buffering to 0 MB for the lowest delay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BehaviorSection: View {
    @Binding var settings: MirrorSettings

    var body: some View {
        Section("Behavior") {
            Toggle("Play phone audio on this Mac", isOn: $settings.audioEnabled)
            Toggle("Show touches on phone", isOn: $settings.showTouches)
            Toggle("Keep phone awake", isOn: $settings.stayAwake)
            Toggle("Turn phone screen off while mirroring", isOn: $settings.turnScreenOffOnStart)
            Toggle("Switch keymaps by game", isOn: $settings.autoKeymap)
            Toggle("Turn the keymap on when its game opens", isOn: $settings.autoEnableKeymap)
                .disabled(!settings.autoKeymap)
        }
    }
}

private struct NoticeBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let notice = model.notice {
            Text(notice)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(3))
                    model.notice = nil
                }
        }
    }
}
