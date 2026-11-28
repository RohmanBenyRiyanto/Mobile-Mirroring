import Components
import DomainModels
import SwiftUI
import Theme

public struct QualityRows: View {
    @Binding public var settings: MirrorSettings

    public init(settings: Binding<MirrorSettings>) { _settings = settings }

    private static let controlWidth: CGFloat = 150

    private func stepperValue(_ value: String, unit: LocalizedStringKey, @ViewBuilder stepper: () -> some View) -> some View {
        HStack(spacing: Theme.Space.s2) {
            Spacer(minLength: 0)
            Text(verbatim: value).font(Theme.Font.mono).frame(minWidth: 32, alignment: .trailing)
            stepper()
            Text(unit).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary.color).frame(width: 34, alignment: .leading)
        }
        .frame(width: Self.controlWidth + 40, alignment: .trailing)
    }

    public var body: some View {
        Group {
            SettingsRow("Codec") {
                Picker("Codec", selection: $settings.quality.codec) {
                    ForEach(VideoCodec.allCases) { Text($0.shortName).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: Self.controlWidth)
            }
            SettingsRow("Max resolution") {
                Picker("Max resolution", selection: $settings.quality.maxSize) {
                    ForEach(ConnectText.options([0, 1280, 1920, 2560, 3840], including: settings.quality.maxSize), id: \.self) {
                        Text($0 == 0 ? String(localized: "Native") : "\($0) px").tag($0)
                    }
                }
                .labelsHidden().frame(width: Self.controlWidth, alignment: .trailing)
            }
            SettingsRow("Bitrate") {
                stepperValue("\(settings.quality.bitRateMbps)", unit: "Mbps") {
                    Stepper("Bitrate", value: $settings.quality.bitRateMbps, in: VideoQuality.bitRateRange).labelsHidden()
                }
            }
            SettingsRow("Frame rate") {
                Picker("Frame rate", selection: $settings.quality.maxFPS) {
                    ForEach(ConnectText.options([30, 60, 90, 120], including: settings.quality.maxFPS), id: \.self) { Text("\($0) fps").tag($0) }
                }
                .labelsHidden().frame(width: Self.controlWidth, alignment: .trailing)
            }
            SettingsRow("Key frame interval") {
                stepperValue("\(settings.quality.keyFrameIntervalSeconds)", unit: "sec") {
                    Stepper("Key frame interval", value: $settings.quality.keyFrameIntervalSeconds, in: VideoQuality.keyFrameIntervalRange).labelsHidden()
                }
            }
            SettingsRow("Constant bitrate", detail: "Steadier picture for OBS") {
                Toggle("Constant bitrate", isOn: $settings.quality.constantBitRate).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}
