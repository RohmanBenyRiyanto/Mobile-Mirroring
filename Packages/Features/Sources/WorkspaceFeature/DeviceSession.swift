import AppKit
import Combine
import SwiftUI
import DomainModels
import InspectorFeature
import KeymapFeature
import Networking
import SystemServices

/// Per-phone mirroring state; the app can hold several of these at once.
@MainActor
public final class DeviceSession: ObservableObject {
    public enum State: Equatable {
        case connecting
        case mirroring
    }

    public let serial: String
    public let settings: MirrorSettings
    public var usesVirtualDisplay: Bool { settings.virtualDisplay.isEnabled }

    @Published public private(set) var state = State.connecting
    @Published public private(set) var deviceName = ""
    @Published public private(set) var videoSize = CGSize(width: 9, height: 16)
    @Published public private(set) var stats = StreamStatistics.Snapshot()
    @Published public private(set) var streamViewerCount = 0
    @Published public private(set) var deviceInfo: DeviceInfo?
    @Published public private(set) var isRecording = false {
        didSet { if !isRecording { recordingStartedAt = nil } }
    }
    @Published public private(set) var recordingStartedAt: Date?
    @Published public private(set) var isMuted = false

    /// The mode this phone is in now, which can change automatically with the keymap.
    @Published public private(set) var modeState: ModeAutoSwitch
    public var mode: WorkspaceMode { modeState.mode }

    public let foreground = ForegroundAppDetector()
    public let scrcpy: ScrcpySession
    public let keymap: KeymapController
    public let inspector: InspectorModel
    public let design: DesignModel
    public let macroRecorder = MacroRecorder()
    public let performance = PerformanceMonitor()
    public let developerTools: DeveloperToolsModel
    public var ledger: PhoneLedgerStore? { didSet { connectLedger() } }
    public let traffic: TrafficModel
    @Published public private(set) var isRecordingMacro = false

    public var onNotice: ((String) -> Void)?
    /// Called when a virtual display takes a shape (landscape or not), so the next start can open that way.
    public var onVirtualDisplayShape: ((_ package: String, _ landscape: Bool) -> Void)?
    public var onSavedFile: ((URL) -> Void)?
    public var keymapIndex: () -> [String: String] = { [:] }
    public var loadKeymapProfile: (String) -> Bool = { _ in false }
    /// Called once when the connection ends by itself (cable pulled, server stopped), with the reason if it was a failure.
    public var onEnded: ((DeviceSession, String?) -> Void)?

    private let adb: ADB
    private var statsTask: Task<Void, Never>?
    private var keymapObserver: AnyCancellable?
    private var foregroundObserver: AnyCancellable?
    private var foregroundForwarder: AnyCancellable?
    private var inspectorObserver: AnyCancellable?
    private var designObserver: AnyCancellable?
    /// True while the keymap is on because the app switched it on (so leaving the game switches it off again).
    private var autoEnabledKeymap = false
    public private(set) var hasEnded = false

    public init(adb: ADB, serial: String, settings: MirrorSettings, cursorCapture: CursorCapturing, mode: WorkspaceMode = .normal) {
        modeState = ModeAutoSwitch(mode: mode)
        self.adb = adb
        developerTools = DeveloperToolsModel(allowsNetworkSwitches: !serial.contains(":"), run: { try String(decoding: adb.run(["-s", serial, "shell", $0], timeout: 8), as: UTF8.self) })
        self.serial = serial
        traffic = TrafficModel(run: { try String(decoding: adb.run(["-s", serial] + $0, timeout: 8), as: UTF8.self) }, adb: adb, serial: serial)
        self.settings = settings
        let scrcpy = ScrcpySession(adb: adb, serial: serial, settings: settings)
        self.scrcpy = scrcpy
        inspector = InspectorModel(fetch: InspectorModel.fetcher(adb: adb, serial: serial))
        design = DesignModel(fetchScreenshot: DesignModel.fetcher(adb: adb, serial: serial))
        keymap = KeymapController(send: { scrcpy.send($0) }, cursor: cursorCapture)
        scrcpy.messageObserver = { [macroRecorder] in macroRecorder.observe($0) }
        scrcpy.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        keymapObserver = keymap.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        inspectorObserver = inspector.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        designObserver = design.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        foregroundObserver = foreground.$current.removeDuplicates().sink { [weak self] app in self?.foregroundChanged(app) }
        // Re-publish foreground changes so views watching this session (such as the logcat window) refresh.
        foregroundForwarder = foreground.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    public var streamURL: String? { scrcpy.streamURL }
    public var streamPort: Int? { settings.obsStreamEnabled ? settings.obsStreamPort : nil }

    public func start() async throws {
        try await Task.detached { [scrcpy] in try scrcpy.start() }.value
    }

    /// Stops on request. Unlike a connection that ends by itself, this does not call `onEnded`.
    public func stop() {
        removePasteFolder()
        scrcpy.stop()
        cleanUp()
    }

    // MARK: Events

    private func handle(_ event: ScrcpySession.Event) {
        guard !hasEnded else { return }
        switch event {
        case let .started(name):
            deviceName = DeviceNameDirectory.bundled.name(model: name) ?? name
            state = .mirroring
            beginMonitoring()
        case let .resized(size):
            videoSize = size
            if usesVirtualDisplay, let app = settings.virtualDisplay.startApp { onVirtualDisplayShape?(app, size.width > size.height) }
            keymap.updateFrameSize(size)
        case let .clipboard(text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            onNotice?(String(localized: "Copied from phone"))
        case .audioUnavailable:
            onNotice?(String(localized: "Audio is unavailable (needs Android 11 or newer)"))
        case let .recordingStopped(url, reason):
            isRecording = false
            recordingStartedAt = nil
            onNotice?(url.map { String(localized: "\(reason). Saved \($0.lastPathComponent)") } ?? reason)
        case let .ended(reason):
            cleanUp()
            onEnded?(self, reason)
        }
    }

    /// A different app came to the front: load, switch on or switch off the keymap as the rules say.
    private func foregroundChanged(_ app: ForegroundApp?) {
        guard settings.autoKeymap, !keymap.isEditing, !hasEnded else { return }
        let actions = KeymapAutoSwitch.actions(foreground: app?.package, index: keymapIndex(), loadedProfileID: keymap.profile?.id,
                                               isEnabled: keymap.isEnabled, wasAutoEnabled: autoEnabledKeymap,
                                               enablesAutomatically: settings.autoEnableKeymap)
        for action in actions {
            switch action {
            case let .load(id):
                guard loadKeymapProfile(id) else { return } // nothing to switch on if it did not load
            case .enable:
                keymap.isEnabled = true
                autoEnabledKeymap = true
                modeState = modeState.keymapTurnedOnAutomatically(enabled: settings.autoGamingMode)
                let keymapName = keymap.profile?.name ?? ""
                onNotice?(String(localized: "Keymap on: \(keymapName) (automatic)"))
            case .disable:
                keymap.isEnabled = false
                autoEnabledKeymap = false
                modeState = modeState.keymapTurnedOffAutomatically()
                onNotice?(String(localized: "Keymap off"))
            }
        }
    }

    /// A previous run may have been killed with the API log's proxy still set; a fresh session removes it.
    private func connectLedger() {
        let serial = self.serial
        developerTools.confirmNetworkOff = { [weak self] in self?.askBeforeNetworkOff() ?? true }
        developerTools.onOwed = { [weak self] baseline in self?.ledger?.recordBaseline(baseline, for: serial) }
        developerTools.onSettled = { [weak self] in self?.ledger?.clearBaseline(for: serial) }
        developerTools.onMockChanged = { [weak self] active in self?.ledger?.setMockLocation(active, for: serial) }
    }

    /// Set by the app model: whether to ask, and the answer to remember.
    var shouldConfirmNetworkOff: () -> Bool = { false }
    var stopAskingAboutNetworkOff: () -> Void = {}

    private func askBeforeNetworkOff() -> Bool {
        guard shouldConfirmNetworkOff() else { return true }
        let answer = Confirmation.ask(title: String(localized: "Turn off the phone's connection?"),
                                      message: String(localized: "Apps on the phone lose the internet until you turn it back on. It is switched back on when you disconnect."),
                                      confirm: String(localized: "Turn Off"))
        if answer.dontAskAgain { stopAskingAboutNetworkOff() }
        return answer.confirmed
    }

    /// Anything an earlier run changed on this phone and never put back (it was killed, the cable was pulled, the battery died) is undone now.
    private func restoreWhatWasLeftBehind() {
        removePasteFolder()
        guard let entry = ledger?.entry(for: serial) else { return }
        let adb = self.adb, serial = self.serial
        Task {
            let current = await Task.detached { () -> DeveloperState in
                let out = (try? adb.run(["-s", serial, "shell", DeveloperSettings.readCommand], timeout: 8)) ?? Data()
                return DeveloperSettings.parse(String(decoding: out, as: UTF8.self))
            }.value
            let commands = PhoneChangeLedger.restoreCommands(for: entry, current: current)
            if !commands.isEmpty {
                _ = await Task.detached { try? adb.run(["-s", serial, "shell", commands.joined(separator: "; ")], timeout: 10) }.value
                if !hasEnded { onNotice?(String(localized: "Put back settings that an earlier session had changed on the phone")) }
            }
            // Only if nothing newer was written meanwhile: this session may already have made changes of its own.
            if ledger?.entry(for: serial) == entry { ledger?.clear(serial) }
        }
    }

    private func removeLeftoverProxy() {
        let adb = self.adb, serial = self.serial
        Task {
            let output = await Task.detached { try? adb.run(["-s", serial, "shell", LeftoverSettings.clearLoopbackProxyCommand], timeout: 6) }.value
            if let output, LeftoverSettings.didClear(String(decoding: output, as: UTF8.self)), !hasEnded {
                onNotice?(String(localized: "Removed a proxy setting left on the phone by an earlier session"))
            }
        }
    }

    private func beginMonitoring() {
        removeLeftoverProxy()
        restoreWhatWasLeftBehind()
        foreground.start(fetch: ForegroundAppDetector.fetcher(adb: adb, serial: serial))

        let adb = self.adb, serial = self.serial
        Task {
            let info = try? await Task.detached { try DeviceInfo.fetch(adb: adb, serial: serial) }.value
            if !hasEnded { deviceInfo = info }
        }

        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                stats = scrcpy.statistics.snapshot()
                streamViewerCount = scrcpy.streamViewerCount
            }
        }
    }

    private func cleanUp() {
        hasEnded = true
        _ = stopMacroRecording()
        keymap.isEnabled = false
        inspector.setOn(false)
        design.reset()
        statsTask?.cancel()
        performance.stop()
        developerTools.restoreOnEnd()
        traffic.stopEverything()
        foreground.stop()
        isRecording = false
    }

    /// Flips the phone's Do Not Disturb; the current state is read first when the Quick Toggles panel has not done so yet.
    public func toggleDoNotDisturb() {
        Task {
            if !developerTools.isLoaded { await developerTools.load() }
            developerTools.change { $0.doNotDisturb.toggle() }
            onNotice?(developerTools.state.doNotDisturb ? String(localized: "Do Not Disturb is on") : String(localized: "Do Not Disturb is off"))
        }
    }

    public func startPerformanceMonitoring() {
        let adb = self.adb, serial = self.serial
        performance.start(package: { [weak self] in self?.foreground.current?.package },
                          fetch: { try String(decoding: adb.run(["-s", serial, "shell", PerformanceProbe.command(package: $0)], timeout: 5), as: UTF8.self) })
    }

    public func setMode(_ mode: WorkspaceMode) { modeState = modeState.chosen(mode) }

    // MARK: Input

    /// The inspector and the design tools both take over the pointer, so only one is on at a time.
    public func setInspecting(_ on: Bool) {
        if on { design.setTool(.off) }
        inspector.setOn(on)
    }

    public func setDesignTool(_ tool: DesignModel.Tool) {
        if tool != .off { inspector.setOn(false) }
        design.setTool(tool)
    }

    public func refreshInspection() {
        inspector.refresh()
        design.refresh()
    }

    /// True while a tool is using the pointer (clicks must not reach the phone).
    public var toolCapturesPointer: Bool { inspector.isOn || design.capturesPointer }

    public func send(_ message: ControlMessage) { scrcpy.send(message) }

    public func press(_ key: AndroidKeyCode) {
        send(.keycode(.down, key))
        send(.keycode(.up, key))
    }

    /// Copied files go to the phone's Download folder; copied text is pasted into the field that has focus.
    public var onFilesPasted: (([URL]) -> Void)?

    public func pasteToPhone() {
        let pasteboard = NSPasteboard.general
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            pasteFiles(files)
            return
        }
        guard let text = pasteboard.string(forType: .string) else { return }
        send(.setClipboard(text, paste: true))
    }

    /// Finder files become the phone's clipboard, so ⌘V in WhatsApp, Gmail and the like attaches them. An .apk or keymap, a folder,
    /// or a phone that refuses the helper falls back to the normal Download copy.
    private func pasteFiles(_ files: [URL]) {
        let isFile = { (url: URL) -> Bool in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
        }
        let ordinary = files.filter { url in isFile(url) && !["apk", KeymapFile.fileExtension].contains(url.pathExtension.lowercased()) }
        let other = files.filter { !ordinary.contains($0) }
        if !other.isEmpty { onFilesPasted?(other) }
        guard !ordinary.isEmpty else { return }
        guard let dex = Bundle.main.url(forResource: "ClipHelper", withExtension: "dex") else { onFilesPasted?(ordinary); return }
        let chosen = Array(ordinary.prefix(PhoneClipboardPlan.maxFiles))
        let tooBig = chosen.contains { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > PhoneClipboardPlan.maxFileBytes }
        guard !tooBig else { onFilesPasted?(ordinary); return }
        onNotice?(String(localized: "Preparing the files for the phone's clipboard"))
        let adb = self.adb, serial = self.serial
        Task {
            let copied = await Task.detached { () -> Int in
                do {
                    let folder = PhoneClipboardPlan.folder
                    _ = try adb.run(["-s", serial, "shell", PhoneClipboardPlan.removeFolderCommand + "; mkdir -p " + PhoneTransfer.shellQuoted(folder)], timeout: 10)
                    var items: [(uri: String, mime: String)] = []
                    for (index, file) in chosen.enumerated() {
                        let name = PhoneClipboardPlan.phoneName(file.lastPathComponent, index: index)
                        let path = "\(folder)/\(name)"
                        _ = try adb.run(["-s", serial, "push", file.path, path], timeout: 600)
                        _ = try? adb.run(["-s", serial, "shell", PhoneTransfer.scanCommand(forPhonePath: path)], timeout: 10)
                        var id: Int?
                        for _ in 0..<10 where id == nil {
                            let out = (try? adb.run(["-s", serial, "shell", PhoneClipboardPlan.queryCommand(forPhonePath: path)], timeout: 8)) ?? Data()
                            id = PhoneClipboardPlan.mediaID(inQueryOutput: String(decoding: out, as: UTF8.self))
                            if id == nil { Thread.sleep(forTimeInterval: 0.2) }
                        }
                        guard let id else { throw NSError(domain: "BenzMirror", code: 1) }
                        items.append((PhoneClipboardPlan.contentURI(forMediaID: id), PhoneClipboardPlan.mimeType(forFileNamed: file.lastPathComponent)))
                    }
                    _ = try adb.run(["-s", serial, "push", dex.path, PhoneClipboardPlan.helperPath], timeout: 20)
                    let out = try adb.run(["-s", serial, "shell", PhoneClipboardPlan.helperCommand(items: items)], timeout: 15)
                    return String(decoding: out, as: UTF8.self).hasPrefix("ok") ? items.count : 0
                } catch { return 0 }
            }.value
            guard !hasEnded else { return }
            if copied > 0 {
                pressWithCtrl(.letterV) // paste straight into the focused field; the clipboard still holds the files if the app ignores it
                onNotice?(copied == 1 ? String(localized: "File pasted into the phone. It is also on the phone's clipboard") : String(localized: "\(copied) files pasted into the phone. They are also on the phone's clipboard"))
            } else {
                onNotice?(String(localized: "Could not use the phone's clipboard, copying to Download instead"))
                onFilesPasted?(ordinary)
            }
        }
    }

    /// The files waited in a folder of their own; they are removed when the session ends and again before the next one.
    private func removePasteFolder() {
        let adb = self.adb, serial = self.serial
        Task.detached { _ = try? adb.run(["-s", serial, "shell", PhoneClipboardPlan.removeFolderCommand + "; rm -f " + PhoneClipboardPlan.helperPath], timeout: 8) }
    }

    public func copyFromPhone() { send(.getClipboard(.copy)) }
    public func cutFromPhone() { send(.getClipboard(.cut)) }

    /// A shortcut the phone understands with Ctrl held (Ctrl+A selects all, Ctrl+Z undoes).
    public func pressWithCtrl(_ key: AndroidKeyCode, extra: KeyMeta = []) {
        send(.keycode(.down, key, meta: [.ctrl, extra]))
        send(.keycode(.up, key, meta: [.ctrl, extra]))
    }

    // MARK: Recording and audio

    public func toggleRecording() {
        if isRecording {
            isRecording = false
            Task {
                do {
                    let url = try await scrcpy.stopRecording()
                    onNotice?(String(localized: "Saved \(url.lastPathComponent) to Movies/\(AppInfo.name)"))
                    onSavedFile?(url)
                } catch {
                    onNotice?(error.localizedDescription)
                }
            }
        } else {
            do {
                let url = try OutputFiles.newURL(in: .moviesDirectory, prefix: "Recording", pathExtension: "mp4", custom: settings.recordingFolder)
                try scrcpy.startRecording(to: url)
                isRecording = true
                recordingStartedAt = Date()
                onNotice?(String(localized: "Recording"))
            } catch {
                onNotice?(error.localizedDescription)
            }
        }
    }

    public func startMacroRecording() {
        macroRecorder.start()
        isRecordingMacro = true
    }

    public func stopMacroRecording() -> [MacroStep] {
        isRecordingMacro = false
        return macroRecorder.stop()
    }

    public func toggleMute() {
        isMuted.toggle()
        scrcpy.isMuted = isMuted
    }
}
