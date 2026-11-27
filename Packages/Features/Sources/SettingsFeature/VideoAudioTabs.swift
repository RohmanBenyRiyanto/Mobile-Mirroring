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
            SettingsRow("Output") {
                Picker("Output", selection: .constant("System default")) { Text("System default").tag("System default") }
                    .labelsHidden().frame(width: 150).disabled(true)
            }
            SettingsRow("Buffer", detail: "Lower is faster. Raise it if sound crackles.") {
                HStack(spacing: Theme.Space.s1) {
                    Text(verbatim: "50").font(Theme.Font.mono)
                    Text("ms").font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary.color)
                }
                .disabled(true)
            }
            SettingsRow("Volume") {
                Slider(value: .constant(0.8)).frame(width: 150).disabled(true)
            }
        }
        SettingsCard(footer: "Output, buffer, volume and recording audio arrive in a later version.") {
            SettingsRow("Mute the phone speaker", detail: "While audio plays on this Mac") {
                Toggle("Mute the phone speaker", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).disabled(true)
            }
            SettingsRow("Include audio in recordings") {
                Toggle("Include audio in recordings", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).disabled(true)
            }
        }
    }
}
