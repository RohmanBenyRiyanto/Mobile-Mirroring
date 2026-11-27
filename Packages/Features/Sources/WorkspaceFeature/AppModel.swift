import AppKit
import Combine
import SwiftUI
import DomainModels
import InspectorFeature
import KeymapFeature
import LogcatFeature
import Networking
import Persistence
import SystemServices

/// The app's state: the phones that can be connected, the phones being mirrored (any number), and
/// the switches that apply to the window. Per-phone state lives in `DeviceSession`; the properties
/// below that mirror it always refer to the active (front) phone.
@MainActor
public final class AppModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case connecting
        case mirroring
        case failed(String)
    }

    private enum Launch: Equatable {
        case idle
        case launching
        case failed(String)
    }

    @Published public private(set) var devices: [AndroidDevice] = []
    @Published public var selectedSerial: String?
    @Published public var settings: MirrorSettings { didSet { SettingsStore.save(settings) } }
    @Published public private(set) var sessions: [DeviceSession] = []
    @Published public private(set) var activeSerial: String?
    /// True while the user is picking another phone to add; the connect screen shows instead of the mirror.
    @Published public var isAddingDevice = false
    @Published public var isStreamMode = false
    @Published public var alwaysOnTop = false
    @Published public var showsStats = false
    @Published public var notice: String?

    /// The keymap editor, while it is open.
    @Published public var editor: KeymapEditorModel?
    @Published public var editorMessage: String?
    @Published private var launch = Launch.idle
    @Published public private(set) var keymapProfiles: [ProfileSummary] = []

    public let adb: ADB?
    public let keymapStore: ProfileStore<Keymap>?
    /// Asks the user before a keymap from outside is saved. Replaceable, so tests need no dialog.
    public var confirmKeymapImport: (KeymapSummary) -> Bool = { ImportPrompt.ask($0) }
    /// Game package → saved keymap id, for switching keymaps by game.
    public private(set) var keymapPackageIndex: [String: String] = [:]
    private var pollTask: Task<Void, Never>?
    private var observers: [String: AnyCancellable] = [:]
    private let noForeground = ForegroundAppDetector()

    private let cursorCapture: CursorCapturing

    /// `cursorCapture` is replaceable so tests never take hold of the real pointer.
    public init(keymapRoot: URL = ProfileStore<Keymap>.defaultRoot(appName: AppInfo.name), cursorCapture: CursorCapturing? = nil) {
        self.cursorCapture = cursorCapture ?? SystemCursorCapture()
        settings = SettingsStore.load()
        keymapStore = try? ProfileStore<Keymap>(kind: "keymap", root: keymapRoot)
        keymapProfiles = keymapStore?.list() ?? []
        keymapPackageIndex = KeymapAutoSwitch.index(from: keymapStore?.loadAll() ?? [])
        adb = ADB.locate()
        if adb == nil { launch = .failed(ADBError.notFound.localizedDescription) }
        startPollingDevices()
    }

    deinit { pollTask?.cancel() }

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
        if found != devices { devices = found }
        if selectedDevice == nil { selectedSerial = found.first(where: \.isReady)?.serial }
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

    /// Whether the front phone is streaming right now.
    public var isMirroring: Bool { active?.state == .mirroring }

    public func connect() {
        guard let adb, let device = selectedDevice, device.isReady, launch != .launching else { return }
        if sessions.contains(where: { $0.serial == device.serial }) { return activate(device.serial) }

        var launchSettings = settings
        launchSettings.obsStreamPort = SessionOrder.streamPort(base: settings.obsStreamPort, taken: Set(sessions.compactMap(\.streamPort)))
        let session = DeviceSession(adb: adb, serial: device.serial, settings: launchSettings, cursorCapture: cursorCapture)
        session.onNotice = { [weak self] in self?.notice = $0 }
        session.keymapIndex = { [weak self] in self?.keymapPackageIndex ?? [:] }
        session.loadKeymapProfile = { [weak self, weak session] id in
            guard let self, let session else { return false }
            return self.loadKeymap(id: id, for: session, announce: false)
        }
        session.onEnded = { [weak self] session, reason in self?.remove(session, reason: reason) }

        launch = .launching
        Task {
            do {
                try await session.start()
                add(session)
            } catch {
                session.stop()
                launch = .failed(error.localizedDescription)
            }
        }
    }

    public func activate(_ serial: String) {
        guard sessions.contains(where: { $0.serial == serial }) else { return }
        activeSerial = serial
        isAddingDevice = false
    }

    /// Stops the front phone.
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
            if let reason { launch = .failed(reason) }
        } else if let reason {
            notice = "\(session.deviceName.isEmpty ? session.serial : session.deviceName): \(reason)"
        }
    }

    // MARK: The front phone (convenience for the views)

    public var session: ScrcpySession? { active?.scrcpy }
    public var deviceName: String { active?.deviceName ?? "" }
    public var videoSize: CGSize { active?.videoSize ?? CGSize(width: 9, height: 16) }
    public var stats: StreamStatistics.Snapshot { active?.stats ?? StreamStatistics.Snapshot() }
    public var streamViewerCount: Int { active?.streamViewerCount ?? 0 }
    public var deviceInfo: DeviceInfo? { active?.deviceInfo }
    public var isRecording: Bool { active?.isRecording ?? false }
    public var isMuted: Bool { active?.isMuted ?? false }
    public var streamURL: String? { active?.streamURL }
    public var foreground: ForegroundAppDetector { active?.foreground ?? noForeground }

    public func send(_ message: ControlMessage) { active?.send(message) }
    public func press(_ key: AndroidKeyCode) { active?.press(key) }
    public func pasteToPhone() { active?.pasteToPhone() }
    public func copyFromPhone() { active?.copyFromPhone() }
    public func toggleRecording() { active?.toggleRecording() }
    public func toggleMute() { active?.toggleMute() }
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
        notice = "Copied \(streamURL)"
    }
}

/// Remembers the user's mirroring settings between launches.
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

extension AppModel: LogcatSource {
    public var frontPackage: String? { foreground.current?.package }
}
