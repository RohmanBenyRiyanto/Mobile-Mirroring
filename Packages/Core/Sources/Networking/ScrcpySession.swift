import Foundation
import DomainModels
import Media

public enum SessionError: LocalizedError {
    case serverExited(String)
    case protocolViolation(String)

    public var errorDescription: String? {
        switch self {
        case let .serverExited(log): return log.isEmpty ? "The device server stopped unexpectedly" : "The device server stopped: \(log)"
        case let .protocolViolation(detail): return "Unexpected data from the device: \(detail)"
        }
    }
}

/// One mirroring session with one device.
///
/// Flow (scrcpy's default "reverse" tunnel, so there is no connect race):
/// push the verified server → listen on loopback → `adb reverse` → start the server →
/// accept the video, audio and control sockets → one reader thread per socket.
public final class ScrcpySession: @unchecked Sendable {
    public enum Event {
        case started(deviceName: String)
        case resized(CGSize)
        case clipboard(String)
        case audioUnavailable
        case recordingStopped(URL?, reason: String)
        case ended(reason: String?)
    }

    /// Hard limits so a faulty or hostile peer cannot make us allocate without bound.
    private enum Limit {
        static let videoPacketBytes = 16 << 20
        static let audioPacketBytes = 1 << 20
        static let clipboardBytes = 1 << 20
        static let frameEdge: UInt32 = 16_384
    }

    private enum AudioCodecID {
        static let raw: UInt32 = 0x0072_6177 // "raw"
        static let disabledByServer: ClosedRange<UInt32> = 0...1
    }

    public let decoder: VideoDecoder
    public let statistics = StreamStatistics()
    /// Delivered from background threads.
    public var onEvent: (@Sendable (Event) -> Void)?
    /// Sees every control message as it is sent (used to record macros). Set once, before the first send.
    public var messageObserver: (@Sendable (ControlMessage) -> Void)?

    private let adb: ADB
    private let serial: String
    private let settings: MirrorSettings
    private let scid = UInt32.random(in: 1...0x7FFF_FFFF)
    private let controlQueue = DispatchQueue(label: "benzmirror.control", qos: .userInteractive)
    private let serverLog = LogTail(limit: 2_000)
    private let player: AudioPlayer?
    private let isAudioStreaming = LockedValue(false)
    private var streamServer: TransportStreamServer?
    private var lastFrameSize: CGSize?

    // Guarded by `lock`.
    private let lock = NSLock()
    private var isFinished = false
    private var didStart = false
    private var video: TCPStream?
    private var audio: TCPStream?
    private var control: TCPStream?
    private var server: Process?
    private var recorder: ScreenRecorder?

    public init(adb: ADB, serial: String, settings: MirrorSettings) {
        precondition(AndroidDevice.isValidSerial(serial))
        self.adb = adb
        self.serial = serial
        self.settings = settings
        self.decoder = VideoDecoder(codec: settings.quality.codec)
        self.player = settings.audioEnabled ? AudioPlayer() : nil
        decoder.onNeedsKeyFrame = { [weak self] in self?.send(.resetVideo) }
    }

    /// Where OBS can read the stream, when the OBS output is enabled.
    public var streamURL: String? { streamServer?.url }
    public var streamViewerCount: Int { streamServer?.viewerCount ?? 0 }

    public var isMuted: Bool {
        get { player?.isMuted ?? false }
        set { player?.isMuted = newValue }
    }

    // MARK: Lifecycle

    /// Blocks until the device is streaming; throws on any setup failure. Call from a background thread.
    public func start() throws {
        do {
            try startStreamServer()
            try connect()
        } catch {
            finish(reason: nil, notify: false)
            throw error
        }
        spawn("benzmirror.video", qos: .userInteractive) { [self] in runLoop(readVideo) }
        spawn("benzmirror.audio", qos: .userInteractive) { [self] in runLoop(readAudio) }
        spawn("benzmirror.device-messages", qos: .utility) { [self] in runLoop(readDeviceMessages) }
    }

    public func stop() {
        finish(reason: nil, notify: false)
    }

    public func send(_ message: ControlMessage) {
        messageObserver?(message)
        controlQueue.async { [weak self] in
            guard let self, let control = self.lock.withLock({ self.control }) else { return }
            do { try control.write(message.serialized) } catch { self.finish(reason: error.localizedDescription, notify: true) }
        }
    }

    // MARK: OBS output

    private func startStreamServer() throws {
        guard settings.obsStreamEnabled else { return }
        let server = try TransportStreamServer(codec: settings.quality.codec, port: UInt16(settings.obsStreamPort),
                                               includesAudio: settings.audioEnabled)
        // A viewer can only start on a key frame; ask the phone for one right away.
        server.onViewerConnected = { [weak self] in self?.send(.resetVideo) }
        server.start()
        streamServer = server
    }

    // MARK: Recording

    public func startRecording(to url: URL) throws {
        guard let format = decoder.currentFormat else { throw RecordingError.noVideoYet }
        let recorder = try ScreenRecorder(url: url, videoFormat: format, includesAudio: isAudioStreaming.get())
        lock.withLock { self.recorder = recorder }
        decoder.setFrameTap { [recorder] sample, isKeyFrame in recorder.appendVideo(sample, isKeyFrame: isKeyFrame) }
    }

    public func stopRecording() async throws -> URL {
        guard let recorder = takeRecorder() else { throw RecordingError.notRecording }
        return try await recorder.finish()
    }

    private func takeRecorder() -> ScreenRecorder? {
        decoder.setFrameTap(nil)
        return lock.withLock {
            defer { recorder = nil }
            return recorder
        }
    }

    // MARK: Setup

    private func connect() throws {
        let jar = try ServerBundle.verifiedURL()
        try adb.run(["-s", serial, "push", jar.path, ServerBundle.remotePath], timeout: 60)

        let listener = try LoopbackListener()
        let tunnel = "localabstract:scrcpy_" + String(format: "%08x", scid)
        try adb.run(["-s", serial, "reverse", tunnel, "tcp:\(listener.port)"])
        defer { _ = try? adb.run(["-s", serial, "reverse", "--remove", tunnel]) }

        let server = try launchServer()
        let alive = { server.isRunning }

        // The server connects in a fixed order: video, audio (if enabled), control.
        let video = try accept(from: listener, serverIsAlive: alive)
        let audio = settings.audioEnabled ? try accept(from: listener, serverIsAlive: alive) : nil
        let control = try accept(from: listener, serverIsAlive: alive)
        lock.withLock {
            self.video = video
            self.audio = audio
            self.control = control
        }

        // The device name arrives on the first socket, followed by the video codec id.
        let name = try video.readExactly(64)
        let deviceName = String(decoding: name.prefix { $0 != 0 }, as: UTF8.self)
        guard try video.readExactly(4).readBigEndian(UInt32.self, at: 0) == settings.quality.codec.wireID else {
            throw SessionError.protocolViolation("video codec")
        }

        lock.withLock { didStart = true }
        if settings.turnScreenOffOnStart { send(.setDisplayPower(false)) }
        onEvent?(.started(deviceName: deviceName))
    }

    private func launchServer() throws -> Process {
        let arguments = ["-s", serial, "shell", "CLASSPATH=\(ServerBundle.remotePath)", "app_process", "/",
                         "com.genymobile.scrcpy.Server", ServerBundle.version] + settings.serverArguments(scid: scid)
        let process = adb.makeProcess(arguments)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [serverLog] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { serverLog.append(chunk) }
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.finish(reason: SessionError.serverExited(self.serverLog.text).localizedDescription, notify: true)
        }
        try process.run()
        lock.withLock { server = process }
        return process
    }

    private func accept(from listener: LoopbackListener, serverIsAlive: () -> Bool) throws -> TCPStream {
        do {
            return try listener.accept(timeout: 10, shouldContinue: serverIsAlive)
        } catch SocketError.timeout where !serverIsAlive() {
            throw SessionError.serverExited(serverLog.text)
        }
    }

    // MARK: Video

    private func readVideo() throws {
        guard let video = lock.withLock({ self.video }) else { return }
        while true {
            let header = try video.readExactly(12)
            if header[header.startIndex] & 0x80 != 0 {
                try handleSessionPacket(header)
            } else {
                try handleVideoPacket(header, from: video)
            }
        }
    }

    private func handleSessionPacket(_ header: Data) throws {
        let width = header.readBigEndian(UInt32.self, at: 4)
        let height = header.readBigEndian(UInt32.self, at: 8)
        guard (1...Limit.frameEdge).contains(width), (1...Limit.frameEdge).contains(height) else {
            throw SessionError.protocolViolation("frame size \(width)x\(height)")
        }
        decoder.beginSession()
        let size = CGSize(width: Int(width), height: Int(height))
        let sizeChanged = lastFrameSize != nil && lastFrameSize != size
        lastFrameSize = size
        onEvent?(.resized(size))

        // A file cannot change frame size midway, so a real size change (rotation) ends the recording.
        if sizeChanged, let recorder = takeRecorder() {
            Task { [onEvent] in
                let url = try? await recorder.finish()
                onEvent?(.recordingStopped(url, reason: "Recording stopped because the screen rotated"))
            }
        }
    }

    private func handleVideoPacket(_ header: Data, from video: TCPStream) throws {
        let flagsAndTime = header.readBigEndian(UInt64.self, at: 0)
        let size = Int(header.readBigEndian(UInt32.self, at: 8))
        guard size <= Limit.videoPacketBytes else { throw SessionError.protocolViolation("video packet of \(size) bytes") }

        let payload = try video.readExactly(size)
        let isConfig = flagsAndTime & (1 << 62) != 0
        let isKeyFrame = flagsAndTime & (1 << 61) != 0
        let presentationTime = Int64(flagsAndTime & ((1 << 61) - 1))
        statistics.recordVideoPacket(bytes: size, isFrame: !isConfig)

        if isConfig {
            try decoder.configure(with: payload)
            streamServer?.submitConfig(payload)
        } else {
            decoder.decode(payload, presentationTime: presentationTime, isKeyFrame: isKeyFrame)
            streamServer?.submitVideo(payload, presentationTime: presentationTime, isKeyFrame: isKeyFrame)
        }
    }

    // MARK: Audio

    private func readAudio() throws {
        guard let audio = lock.withLock({ self.audio }), let player else { return }

        let codecID = try audio.readExactly(4).readBigEndian(UInt32.self, at: 0)
        if AudioCodecID.disabledByServer.contains(codecID) { // phone cannot capture audio (before Android 11)
            streamServer?.disableAudio()
            onEvent?(.audioUnavailable)
            return
        }
        guard codecID == AudioCodecID.raw else { throw SessionError.protocolViolation("audio codec") }

        do { try player.start() } catch {
            streamServer?.disableAudio()
            onEvent?(.audioUnavailable)
            return
        }
        isAudioStreaming.set(true)

        while true {
            let header = try audio.readExactly(12)
            let flagsAndTime = header.readBigEndian(UInt64.self, at: 0)
            let size = Int(header.readBigEndian(UInt32.self, at: 8))
            guard size <= Limit.audioPacketBytes else { throw SessionError.protocolViolation("audio packet of \(size) bytes") }

            let pcm = try audio.readExactly(size)
            let presentationTime = Int64(flagsAndTime & ((1 << 61) - 1))
            player.enqueue(pcm)
            streamServer?.submitAudio(pcm, presentationTime: presentationTime)
            lock.withLock { recorder }?.appendAudio(pcm, presentationTime: presentationTime)
        }
    }

    // MARK: Device messages

    /// Device → client messages arrive on the control socket; they must be drained or the server stalls.
    private func readDeviceMessages() throws {
        guard let control = lock.withLock({ self.control }) else { return }
        while true {
            switch try control.readExactly(1)[0] {
            case 0: // clipboard content
                let length = Int(try control.readExactly(4).readBigEndian(UInt32.self, at: 0))
                guard length <= Limit.clipboardBytes else { throw SessionError.protocolViolation("clipboard size") }
                onEvent?(.clipboard(String(decoding: try control.readExactly(length), as: UTF8.self)))
            case 1: // clipboard set acknowledgement
                _ = try control.readExactly(8)
            case 2: // UHID output, not used
                let size = Int(try control.readExactly(4).readBigEndian(UInt16.self, at: 2))
                _ = try control.readExactly(size)
            default:
                throw SessionError.protocolViolation("device message type")
            }
        }
    }

    // MARK: Teardown

    private func runLoop(_ body: () throws -> Void) {
        do { try body() } catch { finish(reason: error.localizedDescription, notify: true) }
    }

    /// Idempotent. Closes sockets, stops the server and audio, finalizes any recording,
    /// and (optionally) reports why the session ended.
    private func finish(reason: String?, notify: Bool) {
        let teardown: (sockets: [TCPStream?], server: Process?, wasStarted: Bool)? = lock.withLock {
            guard !isFinished else { return nil }
            isFinished = true
            return ([video, audio, control], server, didStart)
        }
        guard let teardown else { return }

        teardown.sockets.forEach { $0?.shutdown() }
        if teardown.server?.isRunning == true { teardown.server?.terminate() }
        player?.stop()
        streamServer?.stop()
        if let recorder = takeRecorder() { Task { _ = try? await recorder.finish() } }
        // Failures during setup are reported by `start()` throwing, not by an event.
        if notify, teardown.wasStarted { onEvent?(.ended(reason: reason)) }
    }

    private func spawn(_ name: String, qos: QualityOfService, _ body: @escaping () -> Void) {
        let thread = Thread(block: body)
        thread.name = name
        thread.qualityOfService = qos
        thread.start()
    }
}

/// Keeps the last few KB of the server's output, for error messages.
private final class LogTail: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var buffer = Data()

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.withLock {
            buffer.append(chunk)
            if buffer.count > limit { buffer = buffer.suffix(limit) }
        }
    }

    var text: String {
        lock.withLock { String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
