import Foundation
import DomainModels
import Media

public final class TransportStreamServer: @unchecked Sendable {
    private static let maxPendingBytes = 8 << 20
    private static let maxRequestBytes = 8 << 10

    private final class Viewer {
        let stream: TCPStream
        let queue = DispatchQueue(label: "benzmirror.stream.viewer")
        let pendingBytes = LockedValue(0)
        var hasKeyFrame = false

        init(stream: TCPStream) { self.stream = stream }
    }

    public let port: UInt16
    public var onViewerConnected: (@Sendable () -> Void)?

    private let listener: LoopbackListener
    private let muxQueue = DispatchQueue(label: "benzmirror.stream.mux", qos: .userInteractive)
    private let isRunning = LockedValue(true)
    private let viewers = LockedValue<[ObjectIdentifier: Viewer]>([:])
    private let audioEncoder: AACEncoder?
    private let codec: VideoCodec

    private var muxer: TransportStreamMuxer
    private var parameterSets = Data()
    private var timeOrigin: Int64?

    public init(codec: VideoCodec, port: UInt16, includesAudio: Bool) throws {
        listener = try LoopbackListener(port: port)
        self.port = listener.port
        self.codec = codec
        audioEncoder = includesAudio ? AACEncoder() : nil
        muxer = TransportStreamMuxer(codec: codec, includesAudio: includesAudio && audioEncoder != nil)
    }

    public var url: String { "http://127.0.0.1:\(port)/live.ts" }
    public var viewerCount: Int { viewers.get().count }

    public func start() {
        let thread = Thread { [self] in acceptLoop() }
        thread.name = "benzmirror.stream.accept"
        thread.start()
    }

    public func stop() {
        isRunning.set(false)
        viewers.withLock { all in
            all.values.forEach { $0.stream.shutdown() }
            all.removeAll()
        }
    }

    public func disableAudio() {
        muxQueue.async { [self] in muxer.includesAudio = false }
    }

    // MARK: Input from the session

    public func submitConfig(_ annexB: Data) {
        muxQueue.async { [self] in parameterSets = annexB }
    }

    public func submitVideo(_ annexB: Data, presentationTime: Int64, isKeyFrame: Bool) {
        muxQueue.async { [self] in
            var accessUnit = Self.accessUnitDelimiter(for: codec)
            if isKeyFrame { accessUnit.append(parameterSets) }
            accessUnit.append(annexB)

            var output = Data()
            if isKeyFrame { output.append(muxer.tables()) }
            output.append(muxer.video(accessUnit, ticks: ticks(presentationTime), isKeyFrame: isKeyFrame))
            broadcast(output, isKeyFrame: isKeyFrame, isVideo: true)
        }
    }

    public func submitAudio(_ pcm: Data, presentationTime: Int64) {
        guard let audioEncoder else { return }
        muxQueue.async { [self] in
            guard muxer.includesAudio else { return }
            for frame in audioEncoder.encode(pcm, presentationTime: presentationTime) {
                broadcast(muxer.audio(frame.adts, ticks: ticks(frame.presentationTime)), isKeyFrame: false, isVideo: false)
            }
        }
    }

    // MARK: Output

    private func ticks(_ microseconds: Int64) -> UInt64 {
        let origin = timeOrigin ?? microseconds
        timeOrigin = origin
        return TransportStreamMuxer.ticks(microseconds: max(microseconds - origin, 0)) + 90_000
    }

    private func broadcast(_ data: Data, isKeyFrame: Bool, isVideo: Bool) {
        for viewer in viewers.get().values {
            if !viewer.hasKeyFrame {
                guard isVideo, isKeyFrame else { continue }
                viewer.hasKeyFrame = true
            }
            guard viewer.pendingBytes.get() < Self.maxPendingBytes else {
                drop(viewer)
                continue
            }
            viewer.pendingBytes.withLock { $0 += data.count }
            viewer.queue.async { [weak self] in
                do { try viewer.stream.write(data) } catch { self?.drop(viewer) }
                viewer.pendingBytes.withLock { $0 -= data.count }
            }
        }
    }

    private func drop(_ viewer: Viewer) {
        viewer.stream.shutdown()
        viewers.withLock { _ = $0.removeValue(forKey: ObjectIdentifier(viewer)) }
    }

    // MARK: Connections

    private func acceptLoop() {
        while isRunning.get() {
            guard let stream = try? listener.accept(timeout: 0.5) else { continue }
            DispatchQueue.global(qos: .userInitiated).async { [self] in welcome(stream) }
        }
    }

    private func welcome(_ stream: TCPStream) {
        stream.setTimeouts(seconds: 2)
        var request = Data()
        while request.count < Self.maxRequestBytes, !request.suffix(4).elementsEqual([13, 10, 13, 10]) {
            guard let chunk = try? stream.readSome(limit: 1_024), !chunk.isEmpty else { return stream.shutdown() }
            request.append(chunk)
        }
        guard request.starts(with: Data("GET ".utf8)) else { return stream.shutdown() }

        let head = "HTTP/1.1 200 OK\r\nContent-Type: video/mp2t\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        guard isRunning.get(), (try? stream.write(Data(head.utf8))) != nil else { return stream.shutdown() }

        let viewer = Viewer(stream: stream)
        viewers.withLock { $0[ObjectIdentifier(viewer)] = viewer }
        onViewerConnected?()
    }

    private static func accessUnitDelimiter(for codec: VideoCodec) -> Data {
        switch codec {
        case .h264: return Data([0, 0, 0, 1, 0x09, 0xF0])
        case .h265: return Data([0, 0, 0, 1, 0x46, 0x01, 0x50])
        }
    }
}
