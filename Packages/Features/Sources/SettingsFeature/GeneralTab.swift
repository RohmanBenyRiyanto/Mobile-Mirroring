import AppKit
import Components
import DomainModels
import ServiceManagement
import SwiftUI
import Theme
import WorkspaceFeature

struct GeneralTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var appearance: AppearanceStore
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        SettingsCard {
            SettingsRow("Language", detail: "Set per app in Language & Region") {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") { NSWorkspace.shared.open(url) }
                }
                .secondaryAction()
            }
            SettingsRow("Open at login", detail: loginError.map { LocalizedStringKey($0) }) {
                Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: setLogin)).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow("Ask before disconnecting", detail: "When leaving the mirror window for the Connect screen") {
                Toggle("Ask before disconnecting", isOn: $model.settings.confirmDisconnect).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow("Mirror when a phone connects") {
                Toggle("Mirror when a phone connects", isOn: $model.settings.mirrorOnConnect).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow("Switch to Gaming mode when a game opens", detail: "Only for games that have a keymap. Off: modes change only when you change them.") {
                Toggle("Switch to Gaming mode when a game opens", isOn: $model.settings.autoGamingMode).labelsHidden().toggleStyle(.switch)
            }
        }

        SettingsCard {
            folderRow("Screenshots", path: $model.settings.screenshotFolder, fallback: .picturesDirectory)
            folderRow("Recordings", path: $model.settings.recordingFolder, fallback: .moviesDirectory)
        }

        AppearanceCard(appearance: appearance)
    }

    private func setLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            opensAtLogin = LoginItem.isEnabled
            loginError = nil
        } catch {
            opensAtLogin = LoginItem.isEnabled
            loginError = error.localizedDescription
        }
    }

    private func folderRow(_ title: LocalizedStringKey, path: Binding<String?>, fallback: FileManager.SearchPathDirectory) -> some View {
        SettingsRow(title) {
            HStack(spacing: Theme.Space.s2) {
                Text(FolderChoice.displayPath(path.wrappedValue, fallback: fallback))
                    .font(Theme.Font.monoCaption).foregroundStyle(Theme.Palette.textSecondary.color).lineLimit(1).truncationMode(.head)
                Button("Choose") { if let chosen = FolderChoice.choose(startingAt: path.wrappedValue) { path.wrappedValue = chosen } }
                    .secondaryAction()
            }
        }
    }
}

struct AppearanceCard: View {
    @ObservedObject var appearance: AppearanceStore

    var body: some View {
        SettingsCard("Appearance") {
            SettingsRow("Mode") {
                Picker("Mode", selection: $appearance.settings.mode) {
                    Text("System").tag(AppearanceSettings.Mode.system)
                    Text("Light").tag(AppearanceSettings.Mode.light)
                    Text("Dark").tag(AppearanceSettings.Mode.dark)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            SettingsRow("Accent", detail: "System follows System Settings") {
                Picker("Accent", selection: $appearance.settings.accent) {
                    Text("System").tag(AppearanceSettings.Accent.system)
                    Text("Benz Blue").tag(AppearanceSettings.Accent.benzBlue)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            SettingsRow("Style", detail: "Liquid Glass is the system's own on macOS 26 and later, imitated before") {
                Picker("Style", selection: $appearance.settings.surface) {
                    Text("Automatic").tag(SurfaceMode.automatic)
                    Text("Liquid Glass").tag(SurfaceMode.glass)
                    Text("Solid").tag(SurfaceMode.solid)
                }
                .labelsHidden().frame(width: 140)
            }
            SettingsRow("App icon", detail: "Shown in the Dock while the app runs") {
                HStack(spacing: Theme.Space.s2) {
                    BrandTile(size: 28, variant: appearance.settings.dockIcon.brandVariant ?? .darkBlue, style: .glass)
                    Picker("App icon", selection: $appearance.settings.dockIcon) {
                        Text("Default").tag(AppearanceSettings.DockIcon.standard)
                        Text("Dark Blue").tag(AppearanceSettings.DockIcon.darkBlue)
                        Text("Clear Blue").tag(AppearanceSettings.DockIcon.clearBlue)
                        Text("Light").tag(AppearanceSettings.DockIcon.light)
                    }
                    .labelsHidden().frame(width: 120)
                }
            }
        }
    }
}

enum FolderChoice {
    /// `~/Pictures/Benz Mirror` for the default; the chosen folder otherwise, with the home folder as `~`.
    static func displayPath(_ custom: String?, fallback: FileManager.SearchPathDirectory) -> String {
        let path = custom ?? FileManager.default.urls(for: fallback, in: .userDomainMask)[0].appendingPathComponent(AppInfo.name).path
        return (path as NSString).abbreviatingWithTildeInPath
    }

    @MainActor
    static func choose(startingAt path: String?) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let path { panel.directoryURL = URL(fileURLWithPath: path) }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// Open-at-login state, backed by the system's login-item service.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
