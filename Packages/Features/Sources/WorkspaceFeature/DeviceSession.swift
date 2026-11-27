import AppKit
import Combine
import SwiftUI
import DomainModels
import InspectorFeature
import KeymapFeature
import Networking
import SystemServices

/// Everything about one phone that is being mirrored: its connection, live numbers and per-phone switches.
/// The app can hold several of these at once.
@MainActor
public final class DeviceSession: ObservableObject {
    public enum State: Equatable {
        case connecting
        case mirroring
    }

    public let serial: String
    public let settings: MirrorSettings

    @Published public private(set) var state = State.connecting
    @Published public private(set) var deviceName = ""
    @Published public private(set) var videoSize = CGSize(width: 9, height: 16)
    @Published public private(set) var stats = StreamStatistics.Snapshot()
    @Published public private(set) var streamViewerCount = 0
    @Published public private(set) var deviceInfo: DeviceInfo?
    @Published public private(set) var isRecording = false
    @Published public private(set) var isMuted = false

    /// The app in front on this phone.
    public let foreground = ForegroundAppDetector()
    public let scrcpy: ScrcpySession
    /// Keyboard-to-touch mapping for this phone.
    public let keymap: KeymapController
    /// Shows what element is under the pointer.
    public let inspector: InspectorModel
    /// Grid, crosshair and colour picker.
    public let design: DesignModel
    /// Records the touches sent to this phone, for macros.
    public let macroRecorder = MacroRecorder()
    @Published public private(set) var isRecordingMacro = false

    /// Short messages for the user ("Saved …").
    public var onNotice: ((String) -> Void)?
    /// Game package → keymap profile id, supplied by the app model.
    public var keymapIndex: () -> [String: String] = { [:] }
    /// Loads a saved keymap into this phone; returns whether it worked. Supplied by the app model.
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

    public init(adb: ADB, serial: String, settings: MirrorSettings, cursorCapture: CursorCapturing) {
        self.adb = adb
        self.serial = serial
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
        // The keymap's menu state follows its controller.
        keymapObserver = keymap.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        inspectorObserver = inspector.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        designObserver = design.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        foregroundObserver = foreground.$current.removeDuplicates().sink { [weak self] app in self?.foregroundChanged(app) }
        // Views that follow the app in front (the logcat window) watch the model, so its changes are re-published.
        foregroundForwarder = foreground.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    public var streamURL: String? { scrcpy.streamURL }
    /// The port this session's OBS stream was asked to use, if the stream is on.
    public var streamPort: Int? { settings.obsStreamEnabled ? settings.obsStreamPort : nil }

    /// Connects to the phone. Throws if it cannot be reached.
    public func start() async throws {
        try await Task.detached { [scrcpy] in try scrcpy.start() }.value
    }

    /// Stops mirroring on request. Does not call `onEnded`.
    public func stop() {
        scrcpy.stop()
        cleanUp()
    }

    // MARK: Events

    private func handle(_ event: ScrcpySession.Event) {
        guard !hasEnded else { return }
        switch event {
        case let .started(name):
            deviceName = name
            state = .mirroring
            beginMonitoring()
        case let .resized(size):
            videoSize = size
            keymap.updateFrameSize(size)
        case let .clipboard(text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            onNotice?("Copied from phone")
        case .audioUnavailable:
            onNotice?("Audio is unavailable (needs Android 11 or newer)")
        case let .recordingStopped(url, reason):
            isRecording = false
            onNotice?(url.map { "\(reason). Saved \($0.lastPathComponent)" } ?? reason)
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
                onNotice?("Keymap on: \(keymap.profile?.name ?? "") (automatic)")
            case .disable:
                keymap.isEnabled = false
                autoEnabledKeymap = false
                onNotice?("Keymap off")
            }
        }
    }

    private func beginMonitoring() {
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
        foreground.stop()
        isRecording = false
    }

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

    public func pasteToPhone() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        send(.setClipboard(text, paste: true))
    }

    public func copyFromPhone() { send(.getClipboard(.copy)) }

    // MARK: Recording and audio

    public func toggleRecording() {
        if isRecording {
            isRecording = false
            Task {
                do {
                    let url = try await scrcpy.stopRecording()
                    onNotice?("Saved \(url.lastPathComponent) to Movies/\(AppInfo.name)")
                } catch {
                    onNotice?(error.localizedDescription)
                }
            }
        } else {
            do {
                let url = try OutputFiles.newURL(in: .moviesDirectory, prefix: "Recording", pathExtension: "mp4")
                try scrcpy.startRecording(to: url)
                isRecording = true
                onNotice?("Recording…")
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
