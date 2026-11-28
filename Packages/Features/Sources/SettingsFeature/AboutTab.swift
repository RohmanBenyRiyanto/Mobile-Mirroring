import Components
import SwiftUI
import Theme
import WorkspaceFeature

/// Who made the app, which version this is, and what it is built on.
struct AboutTab: View {
    var body: some View {
        SettingsCard {
            PlainRow {
                VStack(spacing: Theme.Space.s2) {
                    BrandLogo(height: 64)
                    Text(verbatim: AppInfo.name).font(Theme.Font.title)
                    Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.s3)
            }
        }
        SettingsCard("Creator") {
            SettingsRow("Created by") { Text(verbatim: AppInfo.creator) }
            SettingsRow("Copyright") { Text(verbatim: "© 2026 \(AppInfo.creator)").foregroundStyle(.secondary) }
        }
        SettingsCard("Built on", footer: "Benz Mirror uses the scrcpy server (Apache License 2.0) on the phone. The client on the Mac is written in Swift. Nothing is installed on the phone.") {
            SettingsRow("scrcpy", detail: "Genymobile, Apache License 2.0") {
                Button("Open Website") { if let url = URL(string: "https://github.com/Genymobile/scrcpy") { NSWorkspace.shared.open(url) } }.secondaryAction()
            }
        }
    }
}
