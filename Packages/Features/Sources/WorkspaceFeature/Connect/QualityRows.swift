import Components
import DomainModels
import SwiftUI
import Theme

/// The detailed video controls (codec, resolution, bitrate, frame rate, key frames, constant bitrate) as rows of a card.
/// Used by the Advanced section of the Connect window and by Settings › Video.
public struct QualityRows: View {
    @Binding public var settings: MirrorSettings

    public init(settings: Binding<MirrorSettings>) { _settings = settings }

    public var body: some View {
        Group {
            SettingsRow("Codec") {
                Picker("Codec", selection: $settings.quality.codec) {
                    ForEach(VideoCodec.allCases) { Text($0.shortName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }
            SettingsRow("Max resolution") {
                Picker("Max resolution", selection: $settings.quality.maxSize) {
                    ForEach(ConnectText.options([0, 1280, 1920, 2560, 3840], including: settings.quality.maxSize), id: \.self) {
                        Text($0 == 0 ? String(localized: "Native") : "\($0) px").tag($0)
                    }
                }
                .labelsHidden().frame(width: 120)
            }
            SettingsRow("Bitrate") {
                HStack(spacing: Theme.Space.s1) {
                    Text("\(settings.quality.bitRateMbps)").font(Theme.Font.mono).frame(minWidth: 28, alignment: .trailing)
                    Stepper("Bitrate", value: $settings.quality.bitRateMbps, in: VideoQuality.bitRateRange).labelsHidden()
                    Text("Mbps").font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary.color)
                }
            }
            SettingsRow("Frame rate") {
                Picker("Frame rate", selection: $settings.quality.maxFPS) {
                    ForEach(ConnectText.options([30, 60, 90, 120], including: settings.quality.maxFPS), id: \.self) { Text("\($0) fps").tag($0) }
                }
                .labelsHidden().frame(width: 120)
            }
            SettingsRow("Key frame interval") {
                HStack(spacing: Theme.Space.s1) {
                    Text("\(settings.quality.keyFrameIntervalSeconds)").font(Theme.Font.mono).frame(minWidth: 28, alignment: .trailing)
                    Stepper("Key frame interval", value: $settings.quality.keyFrameIntervalSeconds, in: VideoQuality.keyFrameIntervalRange).labelsHidden()
                    Text("sec").font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary.color)
                }
            }
            SettingsRow("Constant bitrate", detail: "Steadier picture for OBS") {
                Toggle("Constant bitrate", isOn: $settings.quality.constantBitRate).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
