import AppKit
import SwiftUI
import DomainModels
import Persistence

public struct AppCommands: Commands {
    @ObservedObject public var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }
    @Environment(\.openWindow) private var openWindow

    public var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Paste to Phone") { model.pasteToPhone() }
                .keyboardShortcut("v")
                .disabled(!model.isMirroring)
            Button("Copy from Phone") { model.copyFromPhone() }
                .keyboardShortcut("c")
                .disabled(!model.isMirroring)
        }

        CommandMenu("Mirror") {
            Toggle("Stream Mode", isOn: $model.isStreamMode)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!model.isMirroring)
            Toggle("Always on Top", isOn: $model.alwaysOnTop)
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Toggle("Statistics Overlay", isOn: $model.showsStats)
                .keyboardShortcut("i")
                .disabled(!model.isMirroring)
            Button("Actual Pixel Size") { StreamWindow.resizeToActualPixels(videoSize: model.videoSize) }
                .keyboardShortcut("1")
                .disabled(!model.isStreamMode)
            Toggle("UI Inspector", isOn: Binding(get: { model.isInspecting }, set: { model.setInspecting($0) }))
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(!model.isMirroring)
            Button("Refresh Inspector") { model.refreshInspector() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.isInspectorOrDesignOn)
            Divider()
            Button("Copy OBS URL") { model.copyStreamURL() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.streamURL == nil)
            Button("Logcat…") { openWindow(id: "logcat") }
                .keyboardShortcut("l")
        }

        CommandMenu("Design") {
            Picker("Grid", selection: $model.designGrid) {
                ForEach(DesignGrid.allCases) { Text($0.title).tag($0) }
            }
            .disabled(!model.isMirroring)
            Toggle("Crosshair & Ruler", isOn: Binding(get: { model.designTool == .crosshair }, set: { model.setDesignTool($0 ? .crosshair : .off) }))
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .disabled(!model.isMirroring)
            Toggle("Colour Picker", isOn: Binding(get: { model.designTool == .colorPicker }, set: { model.setDesignTool($0 ? .colorPicker : .off) }))
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!model.isMirroring)
        }

        CommandMenu("Keymap") {
            Toggle("Keymap Enabled", isOn: Binding(get: { model.isKeymapEnabled }, set: { model.setKeymapEnabled($0) }))
                .keyboardShortcut("k")
                .disabled(!model.isMirroring)
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
            .disabled(!model.isMirroring)
            Button("Edit Keymap…") { model.startEditingKeymap() }
                .keyboardShortcut("e")
                .disabled(!model.isMirroring || model.editor != nil)
            Button(model.isRecordingMacro ? "Stop Recording Macro" : "Record Macro") { model.toggleMacroRecording() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!model.isMirroring)
            Divider()
            Button("Import Keymap…") { model.importKeymap() }
            Button("Import from Clipboard…") { model.importKeymapFromClipboard() }
            Button("Export Current Keymap…") { if let id = model.currentKeymap?.id { model.exportKeymap(id: id) } }
                .disabled(model.currentKeymap == nil)
            Button("Copy Current Keymap") { if let id = model.currentKeymap?.id { model.copyKeymapToClipboard(id: id) } }
                .disabled(model.currentKeymap == nil)
            Button("Show Keymap Folder") { model.revealKeymapFolder() }
        }

        CommandMenu("Device") {
            ForEach(DeviceTool.allCases) { tool in
                Button(tool.title) { model.run(tool) }
            }
            Divider()
            Button("Screenshot") { model.takeScreenshot() }
                .disabled(!model.isMirroring)
            Button(model.isRecording ? "Stop Recording" : "Start Recording") { model.toggleRecording() }
                .disabled(!model.isMirroring)
        }
    }
}
