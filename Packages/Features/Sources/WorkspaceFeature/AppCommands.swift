import AppKit
import DomainModels
import LogcatFeature
import Persistence
import SwiftUI

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
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.name)") {
                let credits = NSMutableAttributedString(string: AppInfo.creditLine + "\n", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor])
                credits.append(NSAttributedString(string: String(localized: "Built on the scrcpy server (Apache License 2.0)."), attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
                NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
            }
        }
        CommandGroup(replacing: .help) {
            Button("Setup Guide") { model.showsOnboarding = true }
            Button("About and Credits") { model.showSettingsPane("about"); openSettings() }
            Divider()
            Text(verbatim: AppInfo.creditLine)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { model.newTab() }
                .appShortcut("File.New Tab", model: model)
                .disabled(!mirroring)
            Button("Install APK") { model.chooseAPKToInstall() }
                .appShortcut("File.Install APK", model: model)
                .disabled(!mirroring)
            Button("Send File") { model.chooseFileToSend() }
                .appShortcut("File.Send File", model: model)
                .disabled(!mirroring)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") { model.closeTab() }
                .appShortcut("File.Close Tab", model: model)
                .disabled(!mirroring)
        }
    }

    // MARK: Edit

    @CommandsBuilder private var edit: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { model.performEdit(.undo) }.keyboardShortcut("z")
            Button("Redo") { model.performEdit(.redo) }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { model.performEdit(.cut) }.keyboardShortcut("x")
            Button("Copy") { model.performEdit(.copy) }.keyboardShortcut("c")
            Button("Paste") { model.performEdit(.paste) }.keyboardShortcut("v")
            Button("Select All") { model.performEdit(.selectAll) }.keyboardShortcut("a")
            Divider()
            Button("Send Clipboard Image to Phone") { model.sendClipboardImage() }
                .appShortcut("Edit.Send Clipboard Image to Phone", model: model)
                .disabled(!mirroring)
        }
    }

    // MARK: View (the system adds Hide Toolbar and Hide Sidebar)

    @CommandsBuilder private var view: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button(LocalizedStringKey(model.showsStats ? "Hide Statistics" : "Show Statistics")) { model.showsStats.toggle() }
                .appShortcut("View.Statistics", model: model)
                .disabled(!mirroring)
            Button(LocalizedStringKey(model.showsPerformance ? "Hide Developer HUD" : "Show Developer HUD")) { model.showsPerformance.toggle() }
                .appShortcut("View.Developer HUD", model: model)
                .disabled(!mirroring)
            Button(LocalizedStringKey(model.isRailCollapsed ? "Show Control Rail" : "Hide Control Rail")) { model.toggleRail() }
                .appShortcut("View.Control Rail", model: model)
                .disabled(!mirroring)
            Button("Customize Control Rail") { model.showSettingsPane("rail"); openSettings() }
            Toggle("Stream Mode", isOn: $model.isStreamMode)
                .appShortcut("View.Stream Mode", model: model)
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
                .appShortcut("Mirror.Start Mirroring", model: model)
                .disabled(mirroring && !model.isAddingDevice)
            Button("Disconnect") { model.requestDisconnect() }
                .appShortcut("Mirror.Disconnect", model: model)
                .disabled(!mirroring)
            Divider()
            Button("Screenshot") { model.takeScreenshot() }
                .appShortcut("Mirror.Screenshot", model: model)
                .disabled(!mirroring)
            Button("Export Recording as GIF") { model.exportRecordingAsGIF() }
            Button(LocalizedStringKey(model.isRecording ? "Stop Recording" : "Start Recording")) { model.toggleRecording() }
                .appShortcut("Mirror.Start Recording", model: model)
                .disabled(!mirroring)
            Button(LocalizedStringKey(model.isMuted ? "Unmute Audio" : "Mute Audio")) { model.toggleMute() }
                .appShortcut("Mirror.Mute Audio", model: model)
                .disabled(!mirroring)
            Divider()
            Button("Mini Mirror") { openWindow(id: "mini") }
                .appShortcut("Mirror.Mini Mirror", model: model)
                .disabled(!mirroring)
            Toggle("Keep on Top", isOn: $model.alwaysOnTop)
                .appShortcut("Mirror.Keep on Top", model: model)
            Divider()
            Button("Copy OBS URL") { model.copyStreamURL() }
                .appShortcut("Mirror.Copy OBS URL", model: model)
                .disabled(model.streamURL == nil)
            Button("Actual Pixel Size") { StreamWindow.resizeToActualPixels(videoSize: model.videoSize) }
                .appShortcut("Mirror.Actual Pixel Size", model: model)
                .disabled(!mirroring)
        }
    }

    // MARK: Device

    @CommandsBuilder private var device: some Commands {
        CommandMenu("Device") {
            Button("Back") { model.press(.back) }.appShortcut("Device.Back", model: model).disabled(!mirroring)
            Button("Home") { model.press(.home) }.appShortcut("Device.Home", model: model).disabled(!mirroring)
            Button("Recents") { model.press(.appSwitch) }.appShortcut("Device.Recents", model: model).disabled(!mirroring)
            Button("Volume Up") { model.press(.volumeUp) }.appShortcut("Device.Volume Up", model: model).disabled(!mirroring)
            Button("Volume Down") { model.press(.volumeDown) }.appShortcut("Device.Volume Down", model: model).disabled(!mirroring)
            Button("Power") { model.press(.power) }.appShortcut("Device.Power", model: model).disabled(!mirroring)
            Button("Notifications") { model.send(.expandNotificationPanel) }.appShortcut("Device.Notifications", model: model).disabled(!mirroring)
            Button("Quick Settings") { model.send(.expandSettingsPanel) }.appShortcut("Device.Quick Settings", model: model).disabled(!mirroring)
            Button("Rotate") { model.send(.rotateDevice) }.appShortcut("Device.Rotate", model: model).disabled(!mirroring)
            Divider()
            Button("Pair New Device") { model.pairNewDevice() }
            Button("Switch to Wi-Fi") { model.switchToWireless() }
                .appShortcut("Device.Switch to Wi-Fi", model: model)
                .disabled(model.selectedDevice?.isReady != true)
            Button("Device Information") { model.showsDeviceInfo = true }
                .disabled(!mirroring)
            Divider()
            Toggle("UI Inspector", isOn: Binding(get: { model.isInspecting }, set: { model.setInspecting($0) }))
                .appShortcut("Device.UI Inspector", model: model)
                .disabled(!mirroring)
            Toggle("Design Overlay", isOn: Binding(get: { model.designTool == .crosshair }, set: { model.setDesignTool($0 ? .crosshair : .off) }))
                .appShortcut("Device.Design Overlay", model: model)
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
                .appShortcut("Device.Logcat", model: model)
            Button("API Log") { openWindow(id: "apilog") }
                .appShortcut("Device.API Log", model: model)
            Button("Database") { openWindow(id: "database") }
                .appShortcut("Device.Database", model: model)
            Button(LocalizedStringKey(model.showsInspectorPanel ? "Hide Inspector Panel" : "Show Inspector Panel")) { model.showsInspectorPanel.toggle(); if model.showsInspectorPanel { model.setInspecting(true) } }
                .appShortcut("Device.Inspector Panel", model: model)
                .disabled(!mirroring)
            Button(LocalizedStringKey(model.showsQuickToggles ? "Hide Quick Toggles" : "Quick Toggles")) { model.showsQuickToggles.toggle() }
                .appShortcut("Device.Quick Toggles", model: model)
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
                .appShortcut("Keymap.Edit Keymap", model: model)
                .disabled(!mirroring || model.editor != nil)
            Button("Add Tap") { model.addKeymapElement(.tap) }.appShortcut("Keymap.Add Tap", model: model).disabled(!mirroring)
            Button("Add Hold") { model.addKeymapElement(.hold) }.appShortcut("Keymap.Add Hold", model: model).disabled(!mirroring)
            Button("Add Toggle") { model.addKeymapElement(.toggle) }.appShortcut("Keymap.Add Toggle", model: model).disabled(!mirroring)
            Button("Add Joystick") { model.addKeymapElement(.joystick) }.appShortcut("Keymap.Add Joystick", model: model).disabled(!mirroring)
            Button("Add Aim") { model.addKeymapElement(.aim) }.appShortcut("Keymap.Add Aim", model: model).disabled(!mirroring)
            Button("Add Skill Shot") { model.addKeymapElement(.skillShot) }.appShortcut("Keymap.Add Skill Shot", model: model).disabled(!mirroring)
            Button("Add Rapid Tap") { model.addKeymapElement(.turbo) }.appShortcut("Keymap.Add Rapid Tap", model: model).disabled(!mirroring)
            Button("Add Swipe") { model.addKeymapElement(.swipe) }.appShortcut("Keymap.Add Swipe", model: model).disabled(!mirroring)
            Button(LocalizedStringKey(model.isRecordingMacro ? "Stop Recording Macro" : "Record Macro")) { model.toggleMacroRecording() }
                .appShortcut("Keymap.Record Macro", model: model)
                .disabled(!mirroring)
            Button("Revert Changes") { model.revertKeymapChanges() }
                .disabled(model.editor == nil)
            Divider()
            Button("Import Profile") { model.importKeymap() }
            Button("Export Profile") { if let id = model.currentKeymap?.id { model.exportKeymap(id: id) } }
                .disabled(model.currentKeymap == nil)
            Divider()
            Toggle("Keymap Enabled", isOn: Binding(get: { model.isKeymapEnabled }, set: { model.setKeymapEnabled($0) }))
                .appShortcut("Keymap.Keymap Enabled", model: model)
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
                .appShortcut("Logcat.Pause", model: model)
                .disabled(logcat == nil)
            Button("Clear") { logcat?.clear() }
                .appShortcut("Logcat.Clear", model: model)
                .disabled(logcat == nil)
            Button("Filter") { logcat?.focusFilter() }
                .appShortcut("Logcat.Filter", model: model)
                .disabled(logcat == nil)
        }
    }

    // MARK: Window

    @CommandsBuilder private var window: some Commands {
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show Previous Phone") { model.showPhone(offset: -1) }
                .appShortcut("Window.Show Previous Phone", model: model)
                .disabled(model.sessions.count < 2)
            Button("Show Next Phone") { model.showPhone(offset: 1) }
                .appShortcut("Window.Show Next Phone", model: model)
                .disabled(model.sessions.count < 2)
        }
    }
}
