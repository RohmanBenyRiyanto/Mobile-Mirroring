import AppKit
import DomainModels
import KeymapFeature
import Networking
import UniformTypeIdentifiers

/// The actions of the menu bar that are more than a call into the active phone.
extension AppModel {
    // MARK: Files

    /// File ▸ Install APK…
    public func chooseAPKToInstall() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "apk")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose an APK to install on the phone")
        if panel.runModal() == .OK, let url = panel.url { handleDrop([url]) }
    }

    /// File ▸ Send File… (copied to the phone's Download folder)
    public func chooseFileToSend() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose files to copy to the Download folder of the phone")
        if panel.runModal() == .OK { handleDrop(panel.urls.filter { $0.pathExtension.lowercased() != KeymapFile.fileExtension }) }
    }

    // MARK: Tabs (one per phone)

    /// File ▸ New Tab: pick another phone to add.
    public func newTab() { isAddingDevice = true }

    /// File ▸ Close Tab: stops the phone in front.
    public func closeTab() { disconnect() }

    /// Window ▸ Show Next / Previous Phone
    public func showPhone(offset: Int) {
        guard sessions.count > 1, let index = sessions.firstIndex(where: { $0.serial == activeSerial }) else { return }
        activate(sessions[(index + offset + sessions.count) % sessions.count].serial)
    }

    // MARK: View

    public func toggleRail() { isRailCollapsed.toggle() }

    // MARK: Device

    /// Device ▸ Pair New Device…: back to the Connect window with the Wireless sheet open.
    public func pairNewDevice() {
        isAddingDevice = true
        showsWireless = true
    }

    // MARK: Keymap

    /// Keymap ▸ Add Tap / Hold / Toggle / Joystick / Aim / Skill Shot. Opens the editor first if it is not open.
    public func addKeymapElement(_ choice: KeymapEditorModel.Choice) {
        if editor == nil { startEditingKeymap() }
        editor?.addElement(choice)
    }

    /// Keymap ▸ Revert Changes: reopens the editor on the saved keymap, dropping what was changed.
    public func revertKeymapChanges() {
        guard editor != nil else { return }
        closeEditor(save: false)
        startEditingKeymap()
    }
}
