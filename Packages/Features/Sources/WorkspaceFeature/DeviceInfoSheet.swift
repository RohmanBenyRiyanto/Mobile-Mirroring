import Components
import DomainModels
import Networking
import SwiftUI
import Theme

struct DeviceInfoSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var fetched: DeviceInfo?

    private var info: DeviceInfo? { model.deviceInfo ?? fetched }

    var body: some View {
        VStack(spacing: 0) {
            GroupedForm {
                SettingsCard("Device Information") {
                    row("Model", info.map { "\($0.manufacturer) \($0.model)" })
                    row("Android", info.map { "\($0.androidRelease) (API \($0.sdk))" })
                    row("Screen", info.map { "\(Int($0.screenSize.width)) × \(Int($0.screenSize.height)) px" })
                    row("Density", info.map { "\($0.density) dpi · \(String(format: "%.3g", $0.densityScale))×" })
                    if model.isMirroring { row("Picture", "\(Int(model.videoSize.width)) × \(Int(model.videoSize.height)) px") }
                    row("Serial", model.targetSerial)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.prominentAction().keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Space.s4)
        }
        .frame(width: 440, height: 400)
        .task {
            // Before mirroring starts there is no session, so ask the selected phone directly.
            guard model.deviceInfo == nil, let adb = model.adb, let serial = model.targetSerial else { return }
            fetched = try? await Task.detached { try DeviceInfo.fetch(adb: adb, serial: serial) }.value
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String?) -> some View {
        SettingsRow(title) {
            Text(value ?? "—").font(Theme.Font.mono).textSelection(.enabled).foregroundStyle(.secondary)
        }
    }
}
