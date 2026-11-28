import AppKit
import Components
import DomainModels
import Networking
import SwiftUI
import Theme

struct DeviceDetail: View {
    @EnvironmentObject private var model: AppModel
    let status: ConnectStatus
    @Binding var showsWireless: Bool

    var body: some View {
        GroupedForm {
            if let banner = status.banner {
                Section {
                    PlainRow {
                        ConnectBanner(banner: banner, showsWireless: $showsWireless)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            QualityGroup(settings: $model.settings)
            OBSGroup(settings: $model.settings, copy: copyURL)
            BehaviorGroup(settings: $model.settings)
        }
        .animated(value: status.banner)
    }

    private func copyURL(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        model.notice = String(localized: "Copied \(url)")
    }
}

// MARK: Message card

private struct ConnectBanner: View {
    @EnvironmentObject private var model: AppModel
    let banner: ConnectStatus.Banner
    @Binding var showsWireless: Bool

    private static let setupGuide = URL(string: "https://developer.android.com/studio/debug/dev-options")!

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            switch banner {
            case .adbMissing:
                header("exclamationmark.triangle", "adb was not found", isError: true)
                Text("Install the Android platform tools, then reopen the app: brew install android-platform-tools")
            case .noDevice:
                Image(systemName: "iphone").font(.system(size: 22)).foregroundStyle(Theme.Palette.textSecondary.color).frame(maxWidth: .infinity)
                Text("Connect your phone").font(Theme.Font.headline).frame(maxWidth: .infinity)
                Text("Plug it in with a USB cable and turn on USB debugging.").foregroundStyle(Theme.Palette.textSecondary.color).frame(maxWidth: .infinity)
                HStack {
                    Button("Setup Guide…") { model.showsOnboarding = true }
                    Button("Use Wi-Fi…") { showsWireless = true }
                }
                .secondaryAction()
                .frame(maxWidth: .infinity)
            case .unauthorized:
                Text("Allow USB debugging on the phone").font(Theme.Font.emphasized)
                Text("Unlock the phone and tap Allow. Tick “Always allow from this computer”.").foregroundStyle(Theme.Palette.textSecondary.color)
                HStack {
                    Button("Try Again") { model.refreshDevicesNow() }
                    Button("Show Me How…") { NSWorkspace.shared.open(Self.setupGuide) }
                }
                .secondaryAction()
            case .offline:
                Text("The phone stopped responding").font(Theme.Font.emphasized)
                Text("Unplug the cable, plug it in again, then unlock the phone.").foregroundStyle(Theme.Palette.textSecondary.color)
                Button("Reconnect") { model.reconnectDevices() }.secondaryAction()
            case let .failed(message):
                header("exclamationmark.circle", "Mirroring could not start", isError: true)
                Text(message).font(Theme.Font.monoCaption).textSelection(.enabled)
                    .padding(Theme.Space.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Palette.control.color, in: RoundedRectangle(cornerRadius: Theme.Radius.field))
                HStack {
                    Button("Try Again") { model.dismissLaunchError(); model.connect() }
                    Button("Copy Error") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message, forType: .string)
                    }
                }
                .secondaryAction()
            }
        }
        .font(Theme.Font.body)
        .padding(Theme.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.red.color.opacity(0.6), lineWidth: 1).opacity(isError ? 1 : 0))
    }

    private var isError: Bool {
        switch banner {
        case .adbMissing, .failed: return true
        default: return false
        }
    }

    private func header(_ symbol: String, _ title: LocalizedStringKey, isError: Bool) -> some View {
        Label { Text(title).font(Theme.Font.emphasized) } icon: {
            Image(systemName: symbol).foregroundStyle(isError ? Theme.Palette.red.color : Theme.Palette.text.color)
        }
    }
}

// MARK: Quality

private struct QualityGroup: View {
    @EnvironmentObject private var model: AppModel
    @Binding var settings: MirrorSettings
    @State private var showsAdvanced = false

    private static let presets: [QualityPreset] = [.balanced, .high, .gaming, .maximum]
    private let columns = [GridItem(.flexible(), spacing: Theme.Space.s3), GridItem(.flexible(), spacing: Theme.Space.s3)]

    var body: some View {
        SettingsCard("Quality", footer: model.selectedSerial?.contains(":") == true && settings.quality.matchingPreset == .maximum ? "On Wi-Fi, Maximum can stutter. Game streaming or Balanced is steadier." : nil) {
            PlainRow {
                LazyVGrid(columns: columns, spacing: Theme.Space.s3) {
                    ForEach(Self.presets) { preset in
                        if let values = VideoQuality.values(for: preset) {
                            PresetCard(LocalizedStringKey(preset.title), detail: ConnectText.qualitySummary(values),
                                       isSelected: settings.quality.matchingPreset == preset) { settings.quality = values }
                        }
                    }
                }
            }
        }
        SettingsCard {
            Button { withAnimation(Theme.Motion.smooth) { showsAdvanced.toggle() } } label: {
                HStack {
                    Text("Advanced")
                    Spacer()
                    Text(ConnectText.advancedSummary(settings.quality)).font(Theme.Font.monoCaption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showsAdvanced ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        if showsAdvanced {
            SettingsCard { QualityRows(settings: $settings) }
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: OBS

private struct OBSGroup: View {
    @Binding var settings: MirrorSettings
    let copy: (String) -> Void

    private var port: Binding<Int> {
        Binding(get: { settings.obsStreamPort },
                set: { settings.obsStreamPort = min(max($0, MirrorSettings.streamPortRange.lowerBound), MirrorSettings.streamPortRange.upperBound) })
    }

    private var url: String { "http://127.0.0.1:\(settings.obsStreamPort)/live.ts" }

    var body: some View {
        SettingsCard("OBS") {
            Toggle("Send picture to OBS", isOn: $settings.obsStreamEnabled)
            if settings.obsStreamEnabled {
                LabeledContent("Port") {
                    TextField("Port", value: port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).labelsHidden().frame(width: 84)
                }
                MonoField(url) {
                    Button { copy(url) } label: { Label("Copy", systemImage: "doc.on.doc") }.secondaryAction()
                }
                NumberedSteps([
                    "In OBS, add a Media Source.",
                    "Untick Local File. Paste the address into Input and set Input Format to mpegts.",
                    "Set Network Buffering to 0 MB for the lowest delay.",
                ])
            }
        }
    }
}

// MARK: Behavior

private struct BehaviorGroup: View {
    @EnvironmentObject private var model: AppModel
    @Binding var settings: MirrorSettings

    var body: some View {
        SettingsCard("Behavior") {
            row("Audio", "Play phone sound on this Mac", $settings.audioEnabled)
            row("Show touches", "Draw a dot where the screen is touched", $settings.showTouches)
            row("Keep awake", "While connected", $settings.stayAwake)
            row("Screen off", "Mirror with the phone display dark", $settings.turnScreenOffOnStart)
            row("Switch keymaps by game", "Load the keymap that belongs to the game in front", $settings.autoKeymap)
            row("Turn the keymap on when its game opens", nil, $settings.autoEnableKeymap).disabled(!settings.autoKeymap)
        }
        SettingsCard("Separate display", footer: "The app opens on its own display that follows the window size, so there are no black bars. The phone's own screen is not mirrored while this is on. When you disconnect, the app returns to the phone.") {
            row("Use a separate display", "Mirror one app on a display sized to the window", $settings.virtualDisplay.isEnabled)
            if settings.virtualDisplay.isEnabled {
                LabeledContent("App") {
                    TextField("", text: Binding(get: { settings.virtualDisplay.startApp ?? "" }, set: { settings.virtualDisplay.startApp = $0.isEmpty ? nil : $0 }),
                              prompt: Text(verbatim: "com.example.game"))
                        .textFieldStyle(.roundedBorder).font(Theme.Font.mono).multilineTextAlignment(.trailing).frame(width: 220)
                }
                HStack {
                    Spacer()
                    Button("Use app in front") { model.useFrontAppForSeparateDisplay() }
                        .secondaryAction().disabled(model.targetSerial == nil)
                }
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ detail: LocalizedStringKey?, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Text(title)
            if let detail { Text(detail).font(Theme.Font.caption).foregroundStyle(.secondary) }
        }
    }
}
