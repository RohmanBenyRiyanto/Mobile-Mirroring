import AppKit
import Components
import DomainModels
import Networking
import SwiftUI
import Theme
import WorkspaceFeature

struct ShortcutsTab: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var recordingID: String?
    @State private var message: String?
    @State private var monitor: Any?
    @State private var confirmsReset = false

    var body: some View {
        SettingsCard {
            TextField("Search shortcuts", text: $query).textFieldStyle(.roundedBorder).labelsHidden()
        }
        let entries = ShortcutRegistry.items.filter { matches($0) }
        SettingsCard(footer: footer(empty: entries.isEmpty)) {
            ForEach(entries) { item in
                SettingsRow(LocalizedStringKey(item.title)) {
                    HStack(spacing: Theme.Space.s2) {
                        if model.shortcuts.isChanged(item.id) {
                            Button { model.shortcuts.reset(item.id) } label: { Image(systemName: "arrow.uturn.backward") }
                                .buttonStyle(.plain).help("Back to the original shortcut").accessibilityLabel("Back to the original shortcut")
                        }
                        Button { toggleRecording(item.id) } label: {
                            if recordingID == item.id {
                                Text("Press keys").foregroundStyle(.secondary).frame(minWidth: 60)
                            } else if let combo = model.shortcuts.combo(for: item.id) {
                                KeyCap(combo.display)
                            } else {
                                Text("None").foregroundStyle(.secondary).frame(minWidth: 36)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Click, then press the new shortcut. Delete removes it, Esc cancels.")
                    }
                }
            }
        }
        SettingsCard {
            SettingsRow("Reset all shortcuts", detail: "Every menu shortcut goes back to its original") {
                Button("Reset") { confirmsReset = true }.secondaryAction().disabled(model.shortcuts.overrides.isEmpty)
            }
        }
        .confirmationDialog("Reset all shortcuts?", isPresented: $confirmsReset) {
            Button("Reset", role: .destructive) { model.shortcuts = ShortcutBook() }
            Button("Cancel", role: .cancel) {}
        }
        .onDisappear { stopRecording() }
    }

    private func matches(_ item: ShortcutRegistry.Item) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return true }
        let shown = model.shortcuts.combo(for: item.id)?.display.lowercased() ?? ""
        return item.title.lowercased().contains(text) || item.menu.lowercased().contains(text) || shown.contains(text)
    }

    private func footer(empty: Bool) -> LocalizedStringKey? {
        if empty { return "No shortcut matches." }
        if let message { return LocalizedStringKey(message) }
        return "Click a shortcut, then press the new keys."
    }

    private func toggleRecording(_ id: String) {
        stopRecording()
        message = nil
        guard recordingID != id else { recordingID = nil; return }
        recordingID = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: id)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordingID = nil
    }

    private func handle(_ event: NSEvent, for id: String) {
        if event.keyCode == 53 { return stopRecording() }
        if event.keyCode == 51 || event.keyCode == 117, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            model.shortcuts.set(nil, for: id)
            return stopRecording()
        }
        guard let combo = KeyCombo(event: event) else { return }
        if ShortcutRegistry.reserved.contains(combo) {
            message = String(localized: "\(combo.display) is used by macOS or the Edit menu. Pick another shortcut.")
            return
        }
        if let other = model.shortcuts.conflict(for: combo, excluding: id) {
            message = String(localized: "\(combo.display) is already used by \(String(localized: String.LocalizationValue(other.title))). Pick another shortcut.")
            return
        }
        model.shortcuts.set(combo, for: id)
        message = nil
        stopRecording()
    }
}

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
    @State private var adbProblem: String?

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text("adb path")
                HStack(spacing: Theme.Space.s2) {
                    Text(model.adb?.executable.path ?? String(localized: "adb was not found"))
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading).fieldBackground()
                    Button("Choose") { chooseADB() }.secondaryAction()
                    if model.settings.adbPath != nil { Button("Automatic") { _ = model.chooseADB(path: nil) }.secondaryAction() }
                }
                if let adbProblem { Text(adbProblem).font(.caption).foregroundStyle(.red) }
            }
            SettingsRow("adb server", detail: serverState.detail) {
                Button("Restart") { restartServer() }.secondaryAction().disabled(model.adb == nil || serverState == .restarting)
            }
        }
        SettingsCard {
            SettingsRow("Reset all settings", detail: "Asks before anything is removed") {
                Button("Reset") { confirmsReset = true }.secondaryAction()
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

    private func chooseADB() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose the adb program")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = model.adb?.executable.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        adbProblem = model.chooseADB(path: url.path) ? nil : String(localized: "That file is not a working adb")
        Task { await refreshServerState() }
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
        case .checking: return "Checking"
        case .running: return "Running"
        case .stopped: return "Not running"
        case .restarting: return "Restarting"
        }
    }
}
