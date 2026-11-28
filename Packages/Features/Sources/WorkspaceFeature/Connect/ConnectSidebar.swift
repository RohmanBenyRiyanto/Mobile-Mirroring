import Components
import DomainModels
import Networking
import SwiftUI
import Theme

struct ConnectSidebar: View {
    @EnvironmentObject private var model: AppModel
    let openLogcat: () -> Void

    var body: some View {
        List(selection: $model.selectedSerial) {
            Section("Devices") {
                if !model.hasListedDevices {
                    LoadingLabel("Looking for phones")
                } else if model.devices.isEmpty {
                    Text("No devices").foregroundStyle(Theme.Palette.textSecondary.color).transition(.opacity)
                }
                ForEach(model.devices) { device in
                    DeviceRow(device: device).tag(Optional(device.serial))
                }
            }
            Section("Library") {
                libraryButton("Screenshots", "camera") { model.revealLibrary(.screenshots) }
                libraryButton("Recordings", "film") { model.revealLibrary(.recordings) }
                libraryButton("Keymaps", "gamecontroller") { model.revealKeymapFolder() }
                libraryButton("Logcat", "text.alignleft") { openLogcat() }
            }
        }
        .listStyle(.sidebar)
        .animated(value: model.hasListedDevices)
        .animated(value: model.devices.count)
    }

    private func libraryButton(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(Theme.Palette.accentText.color) }
        }
        .buttonStyle(.plain)
    }
}

private struct DeviceRow: View {
    let device: AndroidDevice

    var body: some View {
        HStack(spacing: Theme.Space.s2) {
            Image(systemName: "iphone").foregroundStyle(Theme.Palette.accentText.color)
            VStack(alignment: .leading, spacing: 0) {
                Text(device.title).font(Theme.Font.body)
                Text(ConnectText.deviceStatus(device)).font(Theme.Font.caption).foregroundStyle(Theme.Palette.textSecondary.color)
            }
            Spacer(minLength: 0)
            switch device.state {
            case .unauthorized: Image(systemName: "lock").foregroundStyle(Theme.Palette.textSecondary.color).accessibilityLabel("Unauthorized")
            case .offline, .other: Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.textSecondary.color).accessibilityLabel("Offline")
            case .device: EmptyView()
            }
        }
    }
}

public enum LibraryFolder {
    case screenshots, recordings
}

extension AppModel {
    public func revealLibrary(_ folder: LibraryFolder) {
        let directory: FileManager.SearchPathDirectory = folder == .screenshots ? .picturesDirectory : .moviesDirectory
        let url = FileManager.default.urls(for: directory, in: .userDomainMask)[0].appendingPathComponent(AppInfo.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
