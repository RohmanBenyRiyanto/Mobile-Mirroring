import Components
import DomainModels
import SwiftUI
import Theme

/// Device ▸ Device Information: what is known about the phone being mirrored.
struct DeviceInfoSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            GroupedForm {
                SettingsCard("Device Information") {
                    row("Model", model.deviceInfo.map { "\($0.manufacturer) \($0.model)" })
                    row("Android", model.deviceInfo.map { "\($0.androidRelease) (API \($0.sdk))" })
                    row("Screen", model.deviceInfo.map { "\(Int($0.screenSize.width)) × \(Int($0.screenSize.height)) px" })
                    row("Density", model.deviceInfo.map { "\($0.density) dpi · \(String(format: "%.3g", $0.densityScale))×" })
                    row("Picture", "\(Int(model.videoSize.width)) × \(Int(model.videoSize.height)) px")
                    row("Serial", model.active?.serial)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.prominentAction().keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Space.s4)
        }
        .frame(width: 440, height: 400)
    }

    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        SettingsRow(title) {
            Text(value ?? "—").font(Theme.Font.mono).textSelection(.enabled).foregroundStyle(.secondary)
        }
    }
}
