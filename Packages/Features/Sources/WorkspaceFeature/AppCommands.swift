import AppKit
import DomainModels
import LogcatFeature
import Persistence
import SwiftUI

/// Items whose feature is not built yet are shown but disabled.
public struct AppCommands: Commands {
    @ObservedObject public var model: AppModel
    @FocusedValue(\.logcatActions) private var logcat
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    public init(model: AppModel) {
        self.model = model
    }

    private var mirroring: Bool { model.isMirroring }

    public var body: some Commands {
        file
        edit
        view
        mirror
        device
        keymap
        logcatMenu
        window
    }

    // MARK: File

    @CommandsBuilder private var file: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { model.newTab() }
                .keyboardShortcut("t")
                .disabled(!mirroring)
            Button("Install APK") { model.chooseAPKToInstall() }
                .keyboardShortcut("o")
                .disabled(!mirroring)
            Button("Send File") { model.chooseFileToSend() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!mirroring)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") { model.closeTab() }
                .keyboardShortcut("w")
                .disabled(!mirroring)
        }
    }

    // MARK: Edit

    @CommandsBuilder private var edit: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Paste to Phone") { model.pasteToPhone() }
                .keyboardShortcut("v")
                .disabled(!mirroring)
            Button("Send Clipboard Image to Phone") { model.sendClipboardImage() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(!mirroring)
            Button("Copy from Phone") { model.copyFromPhone() }
                .keyboardShortcut("c")
                .disabled(!mirroring)
        }
    }

    // MARK: View (the system adds Hide Toolbar and Hide Sidebar)

    @CommandsBuilder private var view: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button(LocalizedStringKey(model.showsStats ? "Hide Statistics" : "Show Statistics")) { model.showsStats.toggle() }
                .keyboardShortcut("i")
                .disabled(!mirroring)
            Button(LocalizedStringKey(model.showsPerformance ? "Hide Developer HUD" : "Show Developer HUD")) { model.showsPerformance.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!mirroring)
            Button(LocalizedStringKey(model.isRailCollapsed ? "Show Control Rail" : "Hide Control Rail")) { model.toggleRail() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!mirroring)
            Button("Customize Control Rail") { model.showSettingsPane("rail"); openSettings() }
            Toggle("Stream Mode", isOn: $model.isStreamMode)
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!mirroring)
        }
    }

    // MARK: Mirror

    @CommandsBuilder private var mirror: some Commands {
        CommandMenu("Mirror") {
            Menu("Mode") {
                ForEach(WorkspaceMode.allCases) { mode in
                    Button {
                        model.setMode(mode)
                    } label: {
                        if model.mode == mode { Image(systemName: "checkmark") }
                        Text(mode.title)
                    }
                    .keyboardShortcut(KeyEquivalent(mode.shortcutKey), modifiers: [.command, .option])
                }
            }
            Divider()
            Button("Start Mirroring") { model.connect() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(mirroring && !model.isAddingDevice)
            Button("Disconnect") { model.requestDisconnect() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!mirroring)
            Divider()
            Button("Screenshot") { model.takeScreenshot() }
                .keyboardShortcut("s")
                .disabled(!mirroring)
            Button("Export Recording as GIF") { model.exportRecordingAsGIF() }
            Button(LocalizedStringKey(model.isRecording ? "Stop Recording" : "Start Recording")) { model.toggleRecording() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!mirroring)
            Button(LocalizedStringKey(model.isMuted ? "Unmute Audio" : "Mute Audio")) { model.toggleMute() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!mirroring)
            Divider()
            Button("Mini Mirror") { openWindow(id: "mini") }
                .keyboardShortcut("y", modifiers: [.command, .shift])
                .disabled(!mirroring)
            Toggle("Keep on Top", isOn: $model.alwaysOnTop)
                .keyboardShortcut("y", modifiers: [.command, .option])
            Divider()
            Button("Copy OBS URL") { model.copyStreamURL() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.streamURL == nil)
            Button("Actual Pixel Size") { StreamWindow.resizeToActualPixels(videoSize: model.videoSize) }
                .keyboardShortcut("1")
                .disabled(!mirroring)
        }
    }

    // MARK: Device

    @CommandsBuilder private var device: some Commands {
        CommandMenu("Device") {
            Button("Back") { model.press(.back) }.keyboardShortcut("[").disabled(!mirroring)
            Button("Home") { model.press(.home) }.keyboardShortcut("h", modifiers: [.command, .shift]).disabled(!mirroring)
            Button("Recents") { model.press(.appSwitch) }.keyboardShortcut("a", modifiers: [.command, .shift]).disabled(!mirroring)
            Button("Volume Up") { model.press(.volumeUp) }.keyboardShortcut(.upArrow, modifiers: .command).disabled(!mirroring)
            Button("Volume Down") { model.press(.volumeDown) }.keyboardShortcut(.downArrow, modifiers: .command).disabled(!mirroring)
            Button("Power") { model.press(.power) }.keyboardShortcut("p", modifiers: [.command, .shift]).disabled(!mirroring)
            Button("Notifications") { model.send(.expandNotificationPanel) }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!mirroring)
            Button("Quick Settings") { model.send(.expandSettingsPanel) }.keyboardShortcut("n", modifiers: [.command, .option]).disabled(!mirroring)
            Button("Rotate") { model.send(.rotateDevice) }.keyboardShortcut("r").disabled(!mirroring)
            Divider()
            Button("Pair New Device") { model.pairNewDevice() }
            Button("Switch to Wi-Fi") { model.switchToWireless() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(model.selectedDevice?.isReady != true)
            Button("Device Information") { model.showsDeviceInfo = true }
                .disabled(!mirroring)
            Divider()
            Toggle("UI Inspector", isOn: Binding(get: { model.isInspecting }, set: { model.setInspecting($0) }))
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(!mirroring)
            Toggle("Design Overlay", isOn: Binding(get: { model.designTool == .crosshair }, set: { model.setDesignTool($0 ? .crosshair : .off) }))
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(!mirroring)
            Picker("Grid", selection: $model.designGrid) {
                ForEach(DesignGrid.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .disabled(!mirroring)
            Toggle("Colour Picker", isOn: Binding(get: { model.designTool == .colorPicker }, set: { model.setDesignTool($0 ? .colorPicker : .off) }))
                .disabled(!mirroring)
            Button("Refresh Inspector") { model.refreshInspector() }
                .disabled(!model.isInspectorOrDesignOn)
            Divider()
            Button("Logcat") { openWindow(id: "logcat") }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("API Log") { openWindow(id: "apilog") }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button("Database") { openWindow(id: "database") }
                .keyboardShortcut("d", modifiers: [.command, .option])
            Button(LocalizedStringKey(model.showsInspectorPanel ? "Hide Inspector Panel" : "Show Inspector Panel")) { model.showsInspectorPanel.toggle(); if model.showsInspectorPanel { model.setInspecting(true) } }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(!mirroring)
            Button(LocalizedStringKey(model.showsQuickToggles ? "Hide Quick Toggles" : "Quick Toggles")) { model.showsQuickToggles.toggle() }
                .keyboardShortcut("j", modifiers: [.command, .option])
                .disabled(!mirroring)
            Divider()
            ForEach(DeviceTool.allCases) { tool in
                Button(LocalizedStringKey(tool.title)) { model.run(tool) }.disabled(!mirroring)
            }
        }
    }

    // MARK: Keymap

    @CommandsBuilder private var keymap: some Commands {
        CommandMenu("Keymap") {
            Button("Edit Keymap") { model.startEditingKeymap() }
                .keyboardShortcut("e")
                .disabled(!mirroring || model.editor != nil)
            Button("Add Tap") { model.addKeymapElement(.tap) }.keyboardShortcut("1", modifiers: []).disabled(!mirroring)
            Button("Add Hold") { model.addKeymapElement(.hold) }.keyboardShortcut("2", modifiers: []).disabled(!mirroring)
            Button("Add Toggle") { model.addKeymapElement(.toggle) }.keyboardShortcut("3", modifiers: []).disabled(!mirroring)
            Button("Add Joystick") { model.addKeymapElement(.joystick) }.keyboardShortcut("4", modifiers: []).disabled(!mirroring)
            Button("Add Aim") { model.addKeymapElement(.aim) }.keyboardShortcut("5", modifiers: []).disabled(!mirroring)
            Button("Add Skill Shot") { model.addKeymapElement(.skillShot) }.keyboardShortcut("6", modifiers: []).disabled(!mirroring)
            Button(LocalizedStringKey(model.isRecordingMacro ? "Stop Recording Macro" : "Record Macro")) { model.toggleMacroRecording() }
                .keyboardShortcut("7", modifiers: [])
                .disabled(!mirroring)
            Button("Revert Changes") { model.revertKeymapChanges() }
                .disabled(model.editor == nil)
            Divider()
            Button("Import Profile") { model.importKeymap() }
            Button("Export Profile") { if let id = model.currentKeymap?.id { model.exportKeymap(id: id) } }
                .disabled(model.currentKeymap == nil)
            Divider()
            Toggle("Keymap Enabled", isOn: Binding(get: { model.isKeymapEnabled }, set: { model.setKeymapEnabled($0) }))
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!mirroring)
            Menu("Profile") {
                if model.keymapProfiles.isEmpty { Text("No keymaps yet") }
                ForEach(model.keymapProfiles) { profile in
                    Button {
                        model.loadKeymap(id: profile.id)
                    } label: {
                        if profile.id == model.currentKeymap?.id { Image(systemName: "checkmark") }
                        Text(profile.name)
                    }
                }
            }
            .disabled(!mirroring)
            Button("Import from Clipboard") { model.importKeymapFromClipboard() }
            Button("Copy Current Keymap") { if let id = model.currentKeymap?.id { model.copyKeymapToClipboard(id: id) } }
                .disabled(model.currentKeymap == nil)
            Button("Show Keymap Folder") { model.revealKeymapFolder() }
        }
    }

    // MARK: Logcat (acts on the logcat window in front)

    @CommandsBuilder private var logcatMenu: some Commands {
        CommandMenu("Logcat") {
            Button(LocalizedStringKey(logcat?.isPaused == true ? "Resume" : "Pause")) { logcat?.togglePause() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(logcat == nil)
            Button("Clear") { logcat?.clear() }
                .keyboardShortcut("k")
                .disabled(logcat == nil)
            Button("Filter") { logcat?.focusFilter() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(logcat == nil)
        }
    }

    // MARK: Window

    @CommandsBuilder private var window: some Commands {
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show Previous Phone") { model.showPhone(offset: -1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(model.sessions.count < 2)
            Button("Show Next Phone") { model.showPhone(offset: 1) }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(model.sessions.count < 2)
        }
    }
}
