import Components
import DomainModels
import SwiftUI
import Theme
import WorkspaceFeature

struct VideoTab: View {
    @ObservedObject var model: AppModel

    private var preset: Binding<QualityPreset> {
        Binding(get: { model.settings.quality.matchingPreset },
                set: { if let values = VideoQuality.values(for: $0) { model.settings.quality = values } })
    }

    var body: some View {
        SettingsCard(footer: "Changes apply the next time mirroring starts.") {
            SettingsRow("Default preset") {
                Picker("Default preset", selection: preset) {
                    ForEach(QualityPreset.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .labelsHidden().frame(width: 150)
            }
            QualityRows(settings: $model.settings)
        }
    }
}

struct AudioTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard {
            SettingsRow("Play phone audio on this Mac") {
                Toggle("Play phone audio on this Mac", isOn: $model.settings.audioEnabled).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow("Source", detail: "The microphone needs Android 11 or newer. The phone's own sound is not sent then.") {
                Picker("Source", selection: $model.settings.audioSource) {
                    Text("Phone sound").tag(AudioSource.output)
                    Text("Phone microphone").tag(AudioSource.mic)
                }
                .labelsHidden().frame(width: 170).disabled(!model.settings.audioEnabled)
            }
            SettingsRow("Output") {
                Picker("Output", selection: .constant("System default")) { Text("System default").tag("System default") }
                    .labelsHidden().frame(width: 150).disabled(true)
            }
            SettingsRow("Buffer", detail: "Lower is faster. Raise it if sound crackles. Applies the next time you connect.") {
                HStack(spacing: Theme.Space.s2) {
                    Slider(value: Binding(get: { Double(model.settings.audioBufferMillis) }, set: { model.settings.audioBufferMillis = Int($0) }),
                           in: Double(MirrorSettings.audioBufferRange.lowerBound)...Double(MirrorSettings.audioBufferRange.upperBound), step: 10)
                        .frame(width: 110)
                    Text(verbatim: "\(model.settings.audioBufferMillis) ms").font(Theme.Font.mono).frame(width: 56, alignment: .trailing)
                }
            }
            SettingsRow("Volume") {
                Slider(value: $model.settings.audioVolume, in: 0...1).frame(width: 150)
            }
        }
        SettingsCard(footer: "Output and recording audio arrive in a later version.") {
            SettingsRow("Mute the phone speaker", detail: "While audio plays on this Mac") {
                Toggle("Mute the phone speaker", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).disabled(true)
            }
            SettingsRow("Include audio in recordings") {
                Toggle("Include audio in recordings", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).disabled(true)
            }
        }
    }
}
