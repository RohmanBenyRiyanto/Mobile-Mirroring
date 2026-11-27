import AppKit
import Combine
import Components
import SwiftUI
import DomainModels
import InspectorFeature
import KeymapFeature
import DatabaseFeature
import LogcatFeature
import Networking
import Persistence
import SystemServices

/// App-wide state: the connectable and mirrored phones, and window switches. Per-phone state lives in `DeviceSession`.
@MainActor
public final class AppModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case connecting
        case mirroring
        case failed(String)
    }

    public struct LostConnection: Equatable {
        public let serial: String
        public let name: String
        public let reason: String
        public var attempt = 0
        public var isGivingUp = false
    }

    private enum Launch: Equatable {
        case idle
        case launching
        case failed(String)
    }

    @Published public private(set) var devices: [AndroidDevice] = []
    @Published public var selectedSerial: String?
    @Published public var settings: MirrorSettings { didSet { SettingsStore.save(settings, to: defaults) } }
    @Published public private(set) var sessions: [DeviceSession] = []
    @Published public private(set) var activeSerial: String?
    /// True while the user is picking another phone to add; the connect screen shows instead of the mirror.
    @Published public var isAddingDevice = false
    @Published public var isStreamMode = false
    @Published public var alwaysOnTop = false
    @Published public var showsStats = false
    @Published public var showsOnboarding = false
    @Published public var showsPerformance = false
    @Published public var showsQuickToggles = false
    @Published public var showsInspectorPanel = false
    @Published public var showsWireless = false
    @Published public var showsDeviceInfo = false
    @Published public var railLayout = RailLayout.standard {
        didSet { if let data = try? JSONEncoder().encode(railLayout) { defaults.set(data, forKey: "railLayout.v1") } }
    }
    /// The mode a new phone window starts in (remembered between launches).
    @Published public var defaultMode: WorkspaceMode {
        didSet { defaults.set(defaultMode.rawValue, forKey: "workspaceMode") }
    }
    @Published public var isRailCollapsed = false {
        didSet { defaults.set(isRailCollapsed, forKey: "railCollapsed") }
    }
    @Published public var notice: String? {
        didSet { if notice == nil { noticeFile = nil } }
    }
    /// A file the current notice is about (a screenshot, a recording): the toast offers to show it in Finder.
    @Published public var noticeFile: URL?

    @Published public var editor: KeymapEditorModel?
    @Published public var editorMessage: String?
    @Published private var launch = Launch.idle
    @Published public private(set) var lostConnection: LostConnection?
    @Published public private(set) var keymapProfiles: [ProfileSummary] = []

    public let adb: ADB?
    /// Windows apply this with `themed(_:)`.
    public let appearance: AppearanceStore
    public let keymapStore: ProfileStore<Keymap>?
    /// Asks the user before a keymap from outside is saved. Replaceable, so tests need no dialog.
    public var confirmKeymapImport: (KeymapSummary) -> Bool = { ImportPrompt.ask($0) }
    /// Asks before quitting during a recording. Replaceable, so tests need no dialog.
    public var confirmQuitWhileRecording: () -> Bool = { QuitPrompt.ask() }
    public private(set) var keymapPackageIndex: [String: String] = [:]
    private var pollTask: Task<Void, Never>?
    private var launchTask: Task<Void, Never>?
    private let recordingStatusItem = RecordingStatusItem()
    private var statusObserver: AnyCancellable?
    private var hasListedDevices = false
    private var pendingSession: DeviceSession?
    private var observers: [String: AnyCancellable] = [:]
    private let noForeground = ForegroundAppDetector()

    private let cursorCapture: CursorCapturing
    /// Where settings and window preferences are remembered. Replaceable, so tests never write to the real ones.
    private let defaults: UserDefaults
    private var reconnectTask: Task<Void, Never>?

    public init(keymapRoot: URL = ProfileStore<Keymap>.defaultRoot(appName: AppInfo.name), cursorCapture: CursorCapturing? = nil,
                defaults: UserDefaults = .standard, appearance: AppearanceStore? = nil) {
        self.cursorCapture = cursorCapture ?? SystemCursorCapture()
        self.defaults = defaults
        self.appearance = appearance ?? AppearanceStore(defaults: defaults)
        isRailCollapsed = defaults.bool(forKey: "railCollapsed")
        defaultMode = defaults.string(forKey: "workspaceMode").flatMap(WorkspaceMode.init(rawValue:)) ?? .normal
        railLayout = defaults.data(forKey: "railLayout.v1").flatMap(RailLayout.decode) ?? .standard
        settings = SettingsStore.load(from: defaults)
        showsOnboarding = !defaults.bool(forKey: "onboardingDone")
        keymapStore = try? ProfileStore<Keymap>(kind: "keymap", root: keymapRoot)
        keymapProfiles = keymapStore?.list() ?? []
        keymapPackageIndex = KeymapAutoSwitch.index(from: keymapStore?.loadAll() ?? [])
        adb = ADB.locate()
        if adb == nil { launch = .failed(ADBError.notFound.localizedDescription) }
        startPollingDevices()
        statusObserver = objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshRecordingStatusItem() }
    }

    deinit { pollTask?.cancel() }

    public func finishOnboarding() {
        defaults.set(true, forKey: "onboardingDone")
        showsOnboarding = false
    }

    private func refreshRecordingStatusItem() {
        recordingStatusItem.update(visible: RecordingStatusItem.shouldShow(isStreamMode: isStreamMode, isRecording: isAnyRecording),
                                   startedAt: sessions.first { $0.isRecording }?.recordingStartedAt,
                                   stop: { [weak self] in self?.toggleRecording() }, show: { [weak self] in self?.isStreamMode = false })
    }

    public func refreshKeymaps() {
        keymapProfiles = keymapStore?.list() ?? []
        keymapPackageIndex = KeymapAutoSwitch.index(from: keymapStore?.loadAll() ?? [])
    }

    // MARK: Devices

    public var isAdbMissing: Bool { adb == nil }
    public var selectedDevice: AndroidDevice? { devices.first { $0.serial == selectedSerial } }

    private func startPollingDevices() {
        guard let adb else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let found = await Task.detached { try? adb.devices() }.value ?? []
                self?.updateDevices(found)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func updateDevices(_ found: [AndroidDevice]) {
        let previouslyReady = Set(devices.filter(\.isReady).map(\.serial))
        let isFirstLook = !hasListedDevices
        hasListedDevices = true
        if found != devices { devices = found }
        if selectedDevice == nil { selectedSerial = found.first(where: \.isReady)?.serial }

        // A phone that shows up ready after launch is mirrored by itself when nothing else is mirrored.
        if settings.mirrorOnConnect, !isFirstLook, sessions.isEmpty, launch == .idle,
           let new = found.first(where: { $0.isReady && !previouslyReady.contains($0.serial) }) {
            selectedSerial = new.serial
            connect()
        }
    }

    // MARK: Sessions

    public var active: DeviceSession? { sessions.first { $0.serial == activeSerial } }

    /// The phone that one-shot actions (screenshot, developer toggles, logcat) apply to:
    /// the one in front, or the one chosen on the connect screen.
    public var targetSerial: String? { active?.serial ?? selectedSerial }

    public var state: State {
        switch launch {
        case .launching: return .connecting
        case let .failed(message): return .failed(message)
        case .idle: return isMirroring && !isAddingDevice ? .mirroring : .idle
        }
    }

    public var isMirroring: Bool { active?.state == .mirroring }

    public func connect() {
        guard let adb, let device = selectedDevice, device.isReady, launch != .launching else { return }
        if sessions.contains(where: { $0.serial == device.serial }) { return activate(device.serial) }

        var launchSettings = settings
        launchSettings.obsStreamPort = SessionOrder.streamPort(base: settings.obsStreamPort, taken: Set(sessions.compactMap(\.streamPort)))
        let session = DeviceSession(adb: adb, serial: device.serial, settings: launchSettings, cursorCapture: cursorCapture, mode: defaultMode)
        session.onNotice = { [weak self] in self?.notice = $0 }
        session.onSavedFile = { [weak self] in self?.noticeFile = $0 }
        session.keymapIndex = { [weak self] in self?.keymapPackageIndex ?? [:] }
        session.loadKeymapProfile = { [weak self, weak session] id in
            guard let self, let session else { return false }
            return self.loadKeymap(id: id, for: session, announce: false)
        }
        session.onEnded = { [weak self] session, reason in self?.remove(session, reason: reason) }

        launch = .launching
        pendingSession = session
        launchTask = Task {
            do {
                try await session.start()
                guard !Task.isCancelled else { return session.stop() } // cancelled while the phone was still answering
                pendingSession = nil
                add(session)
            } catch {
                session.stop()
                guard !Task.isCancelled else { return }
                pendingSession = nil
                launch = .failed(error.localizedDescription)
            }
        }
    }

    public func cancelConnect() {
        guard launch == .launching else { return }
        launchTask?.cancel()
        pendingSession?.stop()
        pendingSession = nil
        launch = .idle
    }

    public func dismissLaunchError() { if case .failed = launch { launch = .idle } }

    public func refreshDevicesNow() {
        guard let adb else { return }
        Task {
            let found = await Task.detached { try? adb.devices() }.value ?? []
            updateDevices(found)
        }
    }

    public func reconnectDevices() {
        guard let adb else { return }
        Task {
            _ = await Task.detached { try? adb.run(["reconnect", "offline"], timeout: 10) }.value
            refreshDevicesNow()
        }
    }

    public func activate(_ serial: String) {
        guard sessions.contains(where: { $0.serial == serial }) else { return }
        activeSerial = serial
        isAddingDevice = false
    }

    public func disconnect() {
        guard let session = active else { return }
        session.stop()
        remove(session, reason: nil)
    }

    private func add(_ session: DeviceSession) {
        guard !session.hasEnded else { return launch = .idle } // it dropped while we were finishing the setup
        sessions.append(session)
        // Re-publish the phone's changes so views watching the app model refresh too.
        observers[session.serial] = session.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        activeSerial = session.serial
        isAddingDevice = false
        launch = .idle
    }

    private func remove(_ session: DeviceSession, reason: String?) {
        guard sessions.contains(where: { $0 === session }) else { return }
        activeSerial = SessionOrder.activeSerial(afterRemoving: session.serial, from: sessions.map(\.serial), active: activeSerial)
        sessions.removeAll { $0 === session }
        observers.removeValue(forKey: session.serial)

        if sessions.isEmpty {
            editor = nil
            isStreamMode = false
            isAddingDevice = false
            if let reason { beginReconnecting(serial: session.serial, name: session.deviceName, reason: reason) }
        } else if let reason {
            notice = "\(session.deviceName.isEmpty ? session.serial : session.deviceName): \(reason)"
        }
    }

    // MARK: Connection lost

    private func beginReconnecting(serial: String, name: String, reason: String) {
        lostConnection = LostConnection(serial: serial, name: name.isEmpty ? serial : name, reason: reason)
        startReconnectLoop()
    }

    private func startReconnectLoop() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var attempt = (self?.lostConnection?.attempt ?? 0) + 1
            while let self, let lost = lostConnection, let delay = ReconnectPolicy.delay(forAttempt: attempt) {
                self.lostConnection?.attempt = attempt
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                await attemptReconnect(to: lost.serial)
                if lostConnection == nil || Task.isCancelled { return }
                attempt += 1
            }
            self?.lostConnection?.isGivingUp = true
        }
    }

    private func attemptReconnect(to serial: String) async {
        guard let adb, launch != .launching else { return }
        let found = await Task.detached { try? adb.devices() }.value ?? []
        updateDevices(found)
        guard found.first(where: { $0.serial == serial })?.isReady == true else { return }
        selectedSerial = serial
        connect()
        while launch == .launching { try? await Task.sleep(for: .milliseconds(200)) }
        if sessions.contains(where: { $0.serial == serial }) { lostConnection = nil }
    }

    public func retryNow() {
        guard var lost = lostConnection else { return }
        lost.attempt = 0
        lost.isGivingUp = false
        lostConnection = lost
        startReconnectLoop()
    }

    public func dismissLostConnection() {
        reconnectTask?.cancel()
        reconnectTask = nil
        lostConnection = nil
    }

    // MARK: The front phone (convenience for the views)

    public var session: ScrcpySession? { active?.scrcpy }
    public var deviceName: String { active?.deviceName ?? "" }
    public var videoSize: CGSize { active?.videoSize ?? CGSize(width: 9, height: 16) }
    public var stats: StreamStatistics.Snapshot { active?.stats ?? StreamStatistics.Snapshot() }
    public var streamViewerCount: Int { active?.streamViewerCount ?? 0 }
    public var deviceInfo: DeviceInfo? { active?.deviceInfo }
    public var isRecording: Bool { active?.isRecording ?? false }
    public var recordingStartedAt: Date? { active?.recordingStartedAt }
    public var isMuted: Bool { active?.isMuted ?? false }
    public var streamURL: String? { active?.streamURL }
    public var foreground: ForegroundAppDetector { active?.foreground ?? noForeground }

    public func send(_ message: ControlMessage) { active?.send(message) }
    public func press(_ key: AndroidKeyCode) { active?.press(key) }
    public func pasteToPhone() { active?.pasteToPhone() }
    public func copyFromPhone() { active?.copyFromPhone() }
    public func toggleRecording() { active?.toggleRecording() }
    public func toggleMute() { active?.toggleMute() }
    /// The mode of the phone in front, or the one the next phone will start in.
    public var mode: WorkspaceMode { active?.mode ?? defaultMode }

    public func startPerformanceMonitoring() { active?.startPerformanceMonitoring() }

    public func setMode(_ mode: WorkspaceMode) {
        active?.setMode(mode)
        defaultMode = mode
    }

    /// Esc: leaves Stream Mode, or closes the tool that is open; otherwise it belongs to the phone.
    public func handleEscape() -> Bool {
        if isStreamMode { isStreamMode = false; return true }
        if isInspectorOrDesignOn { setInspecting(false); setDesignTool(.off); return true }
        return false
    }

    public var isInspecting: Bool { active?.inspector.isOn ?? false }
    public func setInspecting(_ on: Bool) { active?.setInspecting(on) }
    public func refreshInspector() { active?.refreshInspection() }
    public var isInspectorOrDesignOn: Bool { active?.toolCapturesPointer ?? false }
    public var designTool: DesignModel.Tool { active?.design.tool ?? .off }
    public func setDesignTool(_ tool: DesignModel.Tool) { active?.setDesignTool(tool) }
    public var designGrid: DesignGrid {
        get { active?.design.grid ?? .off }
        set { active?.design.grid = newValue }
    }

    public func copyStreamURL() {
        guard let streamURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(streamURL, forType: .string)
        notice = String(localized: "Copied \(streamURL)")
    }
}

public enum SettingsStore {
    private static let key = "mirrorSettings.v1"

    public static func load(from defaults: UserDefaults = .standard) -> MirrorSettings {
        guard let data = defaults.data(forKey: key), let settings = try? JSONDecoder().decode(MirrorSettings.self, from: data) else {
            return MirrorSettings()
        }
        return settings
    }

    public static func save(_ settings: MirrorSettings, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}

extension AppModel: DatabaseSource {}

extension AppModel: LogcatSource {
    public var frontPackage: String? { foreground.current?.package }
}
