import AppKit
import Components
import DomainModels
import Networking
import SwiftUI
import Theme
import WorkspaceFeature

struct ShortcutsTab: View {
    @State private var query = ""
    private let catalog = ShortcutCatalog.shared

    var body: some View {
        SettingsCard {
            TextField("Search shortcuts", text: $query).textFieldStyle(.roundedBorder).labelsHidden()
        }
        let entries = catalog.filtered(by: query)
        SettingsCard(footer: entries.isEmpty ? "No shortcut matches." : "Shortcuts are listed as they are in the menu bar. Changing them arrives in a later version.") {
            ForEach(entries) { entry in
                SettingsRow(LocalizedStringKey(entry.title)) {
                    HStack(spacing: Theme.Space.s2) {
                        if catalog.conflict(of: entry) != nil { Image(systemName: "exclamationmark.triangle").accessibilityLabel("Shortcut conflict") }
                        KeyCap(entry.combo.display)
                    }
                }
            }
        }
    }
}

/// A shortcut drawn as a key.
struct KeyCap: View {
    private let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Font.mono)
            .padding(.horizontal, Theme.Space.s2)
            .frame(minWidth: 36, minHeight: 22)
            .background(Theme.Palette.control.color, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.Palette.hairline.color, lineWidth: 1))
    }
}

struct AdvancedTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var appearance: AppearanceStore
    @State private var serverState = AdbServerState.checking
    @State private var confirmsReset = false

    var body: some View {
        SettingsCard {
            SettingsRow("Use bundled adb") {
                Toggle("Use bundled adb", isOn: .constant(false)).labelsHidden().toggleStyle(.switch).disabled(true)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text("adb path")
                HStack(spacing: Theme.Space.s2) {
                    Text(model.adb?.executable.path ?? String(localized: "adb was not found"))
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading).fieldBackground()
                    Button("Choose…") {}.secondaryAction().disabled(true)
                }
            }
            SettingsRow("adb server", detail: serverState.detail) {
                Button("Restart") { restartServer() }.secondaryAction().disabled(model.adb == nil || serverState == .restarting)
            }
        }
        SettingsCard {
            SettingsRow("Hardware video decoding") {
                Toggle("Hardware video decoding", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).disabled(true)
            }
            SettingsRow("App log level") {
                Picker("App log level", selection: .constant("Info")) { Text("Info").tag("Info") }.labelsHidden().frame(width: 100).disabled(true)
            }
        }
        SettingsCard {
            SettingsRow("Reset all settings", detail: "Asks before anything is removed") {
                Button("Reset…") { confirmsReset = true }.secondaryAction()
            }
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmsReset) {
            Button("Reset", role: .destructive) {
                model.settings = MirrorSettings()
                appearance.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Video, audio, behavior and appearance go back to their defaults. Keymaps and recordings are not touched.")
        }
        .task { await refreshServerState() }
    }

    private func restartServer() {
        guard let adb = model.adb else { return }
        serverState = .restarting
        Task {
            _ = await Task.detached { try? adb.run(["kill-server"], timeout: 10) }.value
            _ = await Task.detached { try? adb.run(["start-server"], timeout: 15) }.value
            await refreshServerState()
        }
    }

    private func refreshServerState() async {
        guard let adb = model.adb else { serverState = .stopped; return }
        let running = await Task.detached { (try? adb.run(["get-state"], timeout: 5)) != nil || (try? adb.devices()) != nil }.value
        serverState = running ? .running : .stopped
    }
}

enum AdbServerState: Equatable {
    case checking, running, stopped, restarting

    var detail: LocalizedStringKey {
        switch self {
        case .checking: return "Checking…"
        case .running: return "Running"
        case .stopped: return "Not running"
        case .restarting: return "Restarting…"
        }
    }
}
