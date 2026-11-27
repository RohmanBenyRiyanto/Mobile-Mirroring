import AVFoundation
import CoreMedia
import DomainModels

/// Decodes and displays the encoded stream with the hardware decoder.
///
/// Packet-handling methods must be called from a single (the video) thread.
public final class VideoDecoder: @unchecked Sendable {
    public typealias FrameTap = @Sendable (CMSampleBuffer, _ isKeyFrame: Bool) -> Void

    public let layer = AVSampleBufferDisplayLayer()

    /// Extra places the picture is shown (the mini mirror). They are fed the same frames as `layer`.
    private let extraRenderers = LockedValue<[(layer: AVSampleBufferDisplayLayer, renderer: AVSampleBufferVideoRenderer)]>([])

    /// Creates another layer showing the same picture. Call from the main thread; it starts at the next key frame.
    public func makeMirrorLayer() -> AVSampleBufferDisplayLayer {
        let extra = AVSampleBufferDisplayLayer()
        extra.videoGravity = .resizeAspect
        extra.backgroundColor = CGColor(gray: 0, alpha: 1)
        extraRenderers.withLock { $0.append((extra, extra.sampleBufferRenderer)) }
        onNeedsKeyFrame?()
        return extra
    }

    public func removeMirrorLayer(_ layer: AVSampleBufferDisplayLayer) {
        extraRenderers.withLock { $0.removeAll { $0.layer === layer } }
    }

    /// Called when decoding broke and a fresh key frame is needed.
    public var onNeedsKeyFrame: (() -> Void)?

    private let codec: VideoCodec
    /// Fetched once, where the decoder is created (the main thread); enqueueing is thread-safe.
    private let renderer: AVSampleBufferVideoRenderer
    private let format = LockedValue<CMVideoFormatDescription?>(nil)
    private let frameTap = LockedValue<FrameTap?>(nil)
    private var parameterSets: [Data] = []
    private var waitingForKeyFrame = true

    public init(codec: VideoCodec) {
        self.codec = codec
        renderer = layer.sampleBufferRenderer
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    /// The current stream format, once the device has sent its parameter sets.
    public var currentFormat: CMVideoFormatDescription? { format.get() }

    /// True if the display pipeline rejected a frame and is waiting for a key frame.
    public var hasDisplayError: Bool { renderer.status == .failed }

    /// Receives an independent copy of every frame while set.
    public func setFrameTap(_ tap: FrameTap?) { frameTap.set(tap) }

    /// A new capture session starts (the device rotated): drop everything until its first key frame.
    public func beginSession() {
        waitingForKeyFrame = true
    }

    /// Handles the config packet carrying the parameter sets (SPS/PPS, plus VPS for H.265).
    public func configure(with payload: Data) throws {
        let sets = AnnexB.nalUnits(in: payload).filter(isParameterSet)
        guard !sets.isEmpty else { throw DecoderError.noParameterSets }
        guard sets != parameterSets else { return }

        format.set(try makeFormatDescription(from: sets))
        parameterSets = sets
        waitingForKeyFrame = true
    }

    public func decode(_ payload: Data, presentationTime: Int64, isKeyFrame: Bool) {
        guard let format = format.get() else { return }
        if waitingForKeyFrame {
            guard isKeyFrame else { return }
            waitingForKeyFrame = false
        }

        let frame = AnnexB.lengthPrefixed(payload, excluding: isExcludedFromFrame)
        guard !frame.isEmpty, let sample = SampleBuffers.video(frame, presentationTime: presentationTime, format: format) else { return }

        if let tap = frameTap.get(), let copy = SampleBuffers.video(frame, presentationTime: presentationTime, format: format) {
            tap(copy, isKeyFrame)
        }

        SampleBuffers.markDisplayImmediately(sample)
        renderer.enqueue(sample)
        for extra in extraRenderers.get() {
            extra.renderer.enqueue(sample)
            if extra.renderer.status == .failed { extra.renderer.flush() }
        }
        if renderer.status == .failed {
            renderer.flush()
            waitingForKeyFrame = true
            onNeedsKeyFrame?()
        }
    }

    // MARK: NAL classification

    private func nalType(_ header: UInt8) -> UInt8 {
        codec == .h264 ? header & 0x1F : (header >> 1) & 0x3F
    }

    private func isParameterSet(_ nal: Data) -> Bool {
        guard let header = nal.first else { return false }
        let type = nalType(header)
        return codec == .h264 ? (type == 7 || type == 8) : (32...34).contains(type)
    }

    private func isExcludedFromFrame(_ header: UInt8) -> Bool {
        let type = nalType(header)
        return codec == .h264 ? (7...9).contains(type) : (32...35).contains(type)
    }

    // MARK: Format description

    private func makeFormatDescription(from sets: [Data]) throws -> CMVideoFormatDescription {
        let blob = sets.reduce(into: [UInt8]()) { $0.append(contentsOf: $1) }
        let sizes = sets.map(\.count)
        var offsets: [Int] = []
        var running = 0
        for size in sizes { offsets.append(running); running += size }

        var description: CMVideoFormatDescription?
        let status: OSStatus = blob.withUnsafeBufferPointer { base in
            let pointers = offsets.map { base.baseAddress! + $0 }
            return pointers.withUnsafeBufferPointer { pointerList in
                sizes.withUnsafeBufferPointer { sizeList in
                    switch codec {
                    case .h264:
                        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault, parameterSetCount: sets.count,
                            parameterSetPointers: pointerList.baseAddress!, parameterSetSizes: sizeList.baseAddress!,
                            nalUnitHeaderLength: 4, formatDescriptionOut: &description)
                    case .h265:
                        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                            allocator: kCFAllocatorDefault, parameterSetCount: sets.count,
                            parameterSetPointers: pointerList.baseAddress!, parameterSetSizes: sizeList.baseAddress!,
                            nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &description)
                    }
                }
            }
        }
        guard status == noErr, let description else { throw DecoderError.formatDescription(status) }
        return description
    }
}

public enum DecoderError: LocalizedError {
    case noParameterSets
    case formatDescription(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .noParameterSets: return "The device sent a video config without parameter sets"
        case let .formatDescription(status): return "Could not create the video format (OSStatus \(status))"
        }
    }
}
