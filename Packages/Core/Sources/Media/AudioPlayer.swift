import AVFoundation
import DomainModels

/// Plays the phone's raw PCM audio through the Mac's output.
///
/// Latency stays bounded: if playback ever falls more than `maxQueuedFrames` behind
/// (a stall on the Mac, for example), new audio is dropped instead of queued.
public final class AudioPlayer: @unchecked Sendable {
    public init() {}

    /// 100 ms at 48 kHz.
    public static let maxQueuedFrames: AVAudioFrameCount = 4_800

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SampleBuffers.PCM.sampleRate, channels: 2)!
    private let queuedFrames = LockedValue<AVAudioFrameCount>(0)

    public var isMuted: Bool {
        get { node.volume == 0 }
        set { node.volume = newValue ? 0 : 1 }
    }

    public func start() throws {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        node.play()
    }

    public func stop() {
        node.stop()
        engine.stop()
    }

    /// `pcm` is interleaved little-endian signed 16-bit stereo.
    public func enqueue(_ pcm: Data) {
        let frames = AVAudioFrameCount(pcm.count / SampleBuffers.PCM.bytesPerFrame)
        guard frames > 0, queuedFrames.get() < Self.maxQueuedFrames,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return }

        Self.fill(buffer, fromInterleavedInt16: pcm)
        queuedFrames.withLock { $0 += frames }
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [queuedFrames] _ in
            queuedFrames.withLock { $0 -= min($0, frames) }
        }
    }

    /// Converts interleaved 16-bit samples into the planar floats the engine works with.
    public static func fill(_ buffer: AVAudioPCMBuffer, fromInterleavedInt16 pcm: Data) {
        let frames = min(pcm.count / SampleBuffers.PCM.bytesPerFrame, Int(buffer.frameCapacity))
        buffer.frameLength = AVAudioFrameCount(frames)
        guard let channels = buffer.floatChannelData else { return }

        pcm.withUnsafeBytes { raw in
            for frame in 0..<frames {
                let left = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: frame * 4, as: Int16.self))
                let right = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: frame * 4 + 2, as: Int16.self))
                channels[0][frame] = Float(left) / 32768
                channels[1][frame] = Float(right) / 32768
            }
        }
    }
}
