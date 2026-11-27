import AVFoundation

public enum RecordingError: LocalizedError {
    case noVideoYet
    case notRecording
    case nothingRecorded
    case writerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noVideoYet: return "No video has arrived yet"
        case .notRecording: return "Not recording"
        case .nothingRecorded: return "Nothing was recorded"
        case let .writerFailed(message): return "Recording failed: \(message)"
        }
    }
}

/// Writes the device's stream to an MP4 file.
///
/// The phone's H.264/H.265 packets are stored as-is (no re-encoding, so no quality loss and
/// almost no CPU); audio is encoded to AAC. Every input is appended on one serial queue.
public final class ScreenRecorder: @unchecked Sendable {
    public let url: URL

    private let queue = DispatchQueue(label: "benzmirror.recorder")
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private var startTime: CMTime?
    private var lastVideoTime = CMTime.invalid
    private var isFinished = false

    /// MP4 stores times in ticks of this size. The writer's default (1/600 s) is coarser than the
    /// gap between two quickly repeated frames, which would give them the same timestamp.
    private static let videoTimescale: Int32 = 90_000

    public init(url: URL, videoFormat: CMVideoFormatDescription, includesAudio: Bool) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.mediaTimeScale = Self.videoTimescale
        writer.add(videoInput)

        if includesAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                 AVSampleRateKey: SampleBuffers.PCM.sampleRate,
                                 AVNumberOfChannelsKey: 2,
                                 AVEncoderBitRateKey: 128_000],
                sourceFormatHint: SampleBuffers.pcmFormat)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }

        guard writer.startWriting() else {
            throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "cannot start")
        }
    }

    /// The first frame written must be a key frame, so earlier frames are skipped.
    public func appendVideo(_ sample: CMSampleBuffer, isKeyFrame: Bool) {
        queue.async { [self] in
            guard !isFinished, writer.status == .writing else { return }
            if startTime == nil {
                guard isKeyFrame else { return }
                let start = CMSampleBufferGetPresentationTimeStamp(sample)
                writer.startSession(atSourceTime: start)
                startTime = start
            }
            if videoInput.isReadyForMoreMediaData, let sample = strictlyIncreasing(sample) { videoInput.append(sample) }
        }
    }

    /// Container formats need strictly increasing timestamps; nudge a frame that does not advance.
    private func strictlyIncreasing(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        var time = CMSampleBufferGetPresentationTimeStamp(sample)
        defer { lastVideoTime = time }
        guard lastVideoTime.isValid, CMTimeCompare(time, lastVideoTime) <= 0 else { return sample }

        time = CMTimeAdd(lastVideoTime, CMTime(value: 1, timescale: Self.videoTimescale))
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: time)
        var adjusted: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: 1,
                                              sampleTimingArray: &timing, sampleBufferOut: &adjusted)
        return adjusted
    }

    public func appendAudio(_ pcm: Data, presentationTime: Int64) {
        queue.async { [self] in
            guard !isFinished, writer.status == .writing, let audioInput, let startTime,
                  CMTimeCompare(SampleBuffers.time(microseconds: presentationTime), startTime) >= 0,
                  audioInput.isReadyForMoreMediaData,
                  let sample = SampleBuffers.audio(pcm, presentationTime: presentationTime)
            else { return }
            audioInput.append(sample)
        }
    }

    /// Closes the file. Throws `nothingRecorded` (and deletes the file) if no key frame ever arrived.
    public func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !isFinished else { return continuation.resume(throwing: RecordingError.notRecording) }
                isFinished = true

                guard startTime != nil else {
                    writer.cancelWriting()
                    try? FileManager.default.removeItem(at: url)
                    return continuation.resume(throwing: RecordingError.nothingRecorded)
                }
                videoInput.markAsFinished()
                audioInput?.markAsFinished()
                writer.finishWriting { [writer, url] in
                    if writer.status == .completed {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: RecordingError.writerFailed(writer.error?.localizedDescription ?? "unknown"))
                    }
                }
            }
        }
    }
}
