import AppKit
import DomainModels
import KeymapFeature
import Networking
import UniformTypeIdentifiers

extension AppModel {
    // MARK: Files

    public func chooseAPKToInstall() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "apk")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose an APK to install on the phone")
        if panel.runModal() == .OK, let url = panel.url { handleDrop([url]) }
    }

    public func chooseFileToSend() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose files to copy to the Download folder of the phone")
        if panel.runModal() == .OK { handleDrop(panel.urls.filter { $0.pathExtension.lowercased() != KeymapFile.fileExtension }) }
    }

    // MARK: Tabs (one per phone)

    public func newTab() { isAddingDevice = true }

    public func closeTab() { requestDisconnect() }

    public func showPhone(offset: Int) {
        guard sessions.count > 1, let index = sessions.firstIndex(where: { $0.serial == activeSerial }) else { return }
        activate(sessions[(index + offset + sessions.count) % sessions.count].serial)
    }

    // MARK: View

    public func toggleRail() { isRailCollapsed.toggle() }

    /// Sets the Settings pane to open next, by the raw value of its tab.
    public func showSettingsPane(_ pane: String) { UserDefaults.standard.set(pane, forKey: "settingsTab") }

    // MARK: Device

    public func pairNewDevice() {
        isAddingDevice = true
        showsWireless = true
    }

    // MARK: Keymap

    /// Opens the editor first if it is not already open.
    public func addKeymapElement(_ choice: KeymapEditorModel.Choice) {
        if editor == nil { startEditingKeymap() }
        editor?.addElement(choice)
    }

    public func revertKeymapChanges() {
        guard editor != nil else { return }
        closeEditor(save: false)
        startEditingKeymap()
    }
}
