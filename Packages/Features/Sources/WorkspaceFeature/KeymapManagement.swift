import AppKit
import Foundation
import UniformTypeIdentifiers
import DomainModels
import KeymapFeature
import Persistence
import SystemServices

/// Shared keymaps are JSON with their own extension, so drops and double-clicks can recognise them.
public enum KeymapFile {
    public static let fileExtension = "benzkeymap"
    public static let typeIdentifier = "dev.benz.mirror.keymap"

    public static var contentTypes: [UTType] {
        [UTType(typeIdentifier), UTType(filenameExtension: fileExtension, conformingTo: .json), .json].compactMap { $0 }
    }
}

@MainActor
public enum ImportPrompt {
    public static func ask(_ summary: KeymapSummary) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Import the keymap “\(summary.name)”?"
        alert.informativeText = summary.message
        alert.alertStyle = summary.warnings.isEmpty ? .informational : .warning
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

extension AppModel {
    public var isKeymapEnabled: Bool { active?.keymap.isEnabled ?? false }
    public var currentKeymap: ProfileSummary? { active?.keymap.profile }

    /// Makes a saved keymap the front phone's keymap (it still has to be switched on).
    public func loadKeymap(id: String) {
        guard let active else { return }
        loadKeymap(id: id, for: active, announce: true)
    }

    /// Returns false when the keymap fails to load; the reason is shown as a notice.
    @discardableResult
    public func loadKeymap(id: String, for session: DeviceSession, announce: Bool) -> Bool {
        guard let keymapStore else { return false }
        do {
            let profile = try keymapStore.load(id: id)
            let keymap = try profile.payload.validated()
            session.keymap.load(keymap, profile: ProfileSummary(id: profile.id, name: profile.name, modified: profile.modified))
            if announce { notice = String(localized: "Keymap: \(profile.name)") }
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    public func setKeymapEnabled(_ enabled: Bool) {
        guard let keymap = active?.keymap else { return }
        guard !enabled || keymap.hasKeymap else {
            notice = String(localized: "Choose a keymap first (Keymap menu → Profile)")
            return
        }
        keymap.isEnabled = enabled
        let keymapName = keymap.profile?.name ?? ""
        notice = enabled ? String(localized: "Keymap on: \(keymapName)") : String(localized: "Keymap off")
    }

    // MARK: Sharing

    public func importKeymap() {
        guard keymapStore != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = KeymapFile.contentTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Benz Mirror keymap file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importKeymap(from: url)
    }

    public func importKeymap(from url: URL) {
        do {
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard size <= ProfileFormat.maxBytes else { throw ProfileError.tooLarge }
            importKeymap(data: try Data(contentsOf: url), source: url.lastPathComponent)
        } catch {
            notice = String(localized: "Import failed: \(error.localizedDescription)")
        }
    }

    public func importKeymapFromClipboard(pasteboard: NSPasteboard = .general) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            notice = String(localized: "The clipboard has no text to import")
            return
        }
        guard text.utf8.count <= ProfileFormat.maxBytes else {
            notice = String(localized: "Import failed: \(ProfileError.tooLarge.localizedDescription)")
            return
        }
        importKeymap(data: Data(text.utf8), source: "the clipboard")
    }

    /// Validates the keymap and asks the user before saving anything.
    @discardableResult
    public func importKeymap(data: Data, source: String) -> Bool {
        guard let keymapStore else { return false }
        do {
            guard data.count <= ProfileFormat.maxBytes else { throw ProfileError.tooLarge }
            let profile = try keymapStore.inspect(data)
            _ = try profile.payload.validated() // refuse what could not be used before asking anything
            guard confirmKeymapImport(KeymapSummary(profile: profile, existingIDs: keymapStore.identifiers())) else {
                notice = String(localized: "Import cancelled")
                return false
            }
            let imported = try keymapStore.importData(data)
            refreshKeymaps()
            loadKeymap(id: imported.id)
            notice = String(localized: "Imported \(imported.name) from \(source)")
            return true
        } catch {
            notice = String(localized: "Import failed: \(error.localizedDescription)")
            return false
        }
    }

    public func exportKeymap(id: String) {
        guard let keymapStore else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = KeymapFile.contentTypes
        panel.nameFieldStringValue = "\(id).\(KeymapFile.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try keymapStore.exportData(id: id).write(to: url, options: .atomic)
            notice = String(localized: "Exported \(url.lastPathComponent)")
        } catch {
            notice = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    public func copyKeymapToClipboard(id: String, pasteboard: NSPasteboard = .general) {
        do {
            let data = try keymapStore?.exportData(id: id) ?? Data()
            pasteboard.clearContents()
            pasteboard.setString(String(decoding: data, as: UTF8.self), forType: .string)
            notice = String(localized: "Keymap copied. Paste it anywhere; others can use Import from Clipboard.")
        } catch {
            notice = String(localized: "Copy failed: \(error.localizedDescription)")
        }
    }

    public func revealKeymapFolder() {
        guard let folder = keymapStore?.directory else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    // MARK: Macros

    public var isRecordingMacro: Bool { active?.isRecordingMacro ?? false }

    /// First use starts recording the touches sent to the phone; the second stops, asks for a key, and saves the macro.
    public func toggleMacroRecording() {
        guard let active else { return }
        guard active.isRecordingMacro else {
            active.startMacroRecording()
            notice = String(localized: "Recording a macro. Use the phone, then choose Stop Recording Macro.")
            return
        }

        let steps = active.stopMacroRecording()
        guard !steps.isEmpty else {
            notice = String(localized: "Nothing was recorded")
            return
        }
        notice = String(localized: "Press the key for this macro (Esc cancels)")
        Task {
            guard let key = await KeyCapture.next() else { return notice = String(localized: "Macro discarded") }
            saveMacro(steps, key: key)
        }
    }

    /// Adds a recorded macro, bound to `key`, to the current keymap (or to a "Macros" keymap if none is loaded).
    public func saveMacro(_ steps: [MacroStep], key: UInt16) {
        guard let keymapStore, let active, let first = steps.first else { return }
        do {
            let id = active.keymap.profile?.id ?? "macros"
            var profile = (try? keymapStore.load(id: id)) ?? Profile(id: id, name: "Macros", payload: Keymap())

            let number = profile.payload.elements.filter { if case .macro = $0.action { return true } else { return false } }.count + 1
            profile.payload.elements.append(KeymapElement(label: "Macro \(number)", position: first.position,
                                                          action: .macro(key: key, steps: steps, loop: false, speed: 1)))
            _ = try profile.payload.validated() // never save a keymap that could not be loaded again

            let saved = try keymapStore.save(profile)
            refreshKeymaps()
            loadKeymap(id: saved.id)
            let keyName = KeyNames.name(for: key)
            notice = String(localized: "Macro \(number) saved on \(keyName) in \(saved.name)")
        } catch {
            notice = String(localized: "Could not save the macro: \(error.localizedDescription)")
        }
    }

    // MARK: Editor

    /// The keymap is switched off while the editor is open.
    public func startEditingKeymap() {
        guard let active, editor == nil else { return }
        let profile = active.keymap.profile.flatMap { try? keymapStore?.load(id: $0.id) }
        active.keymap.isEditing = true
        isStreamMode = false
        editorMessage = nil
        editor = KeymapEditorModel(profile: profile)
    }

    @discardableResult
    public func saveEditor() -> Bool {
        guard let editor, let keymapStore else { return false }
        do {
            let saved = try editor.save(into: keymapStore)
            editorMessage = nil
            refreshKeymaps()
            loadKeymap(id: saved.id)
            notice = String(localized: "Saved \(saved.name)")
            return true
        } catch {
            editorMessage = error.localizedDescription
            return false
        }
    }

    public func closeEditor(save: Bool) {
        if save, !saveEditor() { return } // stay open so the problem can be fixed
        editor = nil
        editorMessage = nil
        active?.keymap.isEditing = false
    }
}
