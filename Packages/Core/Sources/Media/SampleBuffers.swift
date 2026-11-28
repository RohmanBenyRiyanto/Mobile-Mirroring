import CoreMedia
import Foundation

public enum SampleBuffers {
    private static let timescale: CMTimeScale = 1_000_000

    public static func time(microseconds: Int64) -> CMTime {
        CMTime(value: microseconds, timescale: timescale)
    }

    public static func video(_ frame: Data, presentationTime: Int64, format: CMVideoFormatDescription) -> CMSampleBuffer? {
        let stamp = time(microseconds: presentationTime)
        return makeSample(frame, format: format, sampleCount: 1,
                          timing: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: stamp, decodeTimeStamp: stamp))
    }

    public static func audio(_ pcm: Data, presentationTime: Int64) -> CMSampleBuffer? {
        let frames = pcm.count / PCM.bytesPerFrame
        guard frames > 0, let format = pcmFormat else { return nil }
        let timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(PCM.sampleRate)),
                                        presentationTimeStamp: time(microseconds: presentationTime),
                                        decodeTimeStamp: .invalid)
        return makeSample(pcm.prefix(frames * PCM.bytesPerFrame), format: format, sampleCount: frames, timing: timing)
    }

    public static func markDisplayImmediately(_ sample: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0
        else { return }
        let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dictionary,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }

    // MARK: Internals

    public enum PCM {
        public static let sampleRate = 48_000.0
        public static let channelCount: UInt32 = 2
        public static let bytesPerFrame = 4
    }

    public static let pcmFormat: CMAudioFormatDescription? = {
        var description = AudioStreamBasicDescription(
            mSampleRate: PCM.sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(PCM.bytesPerFrame), mFramesPerPacket: 1, mBytesPerFrame: UInt32(PCM.bytesPerFrame),
            mChannelsPerFrame: PCM.channelCount, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        return format
    }()

    private static func makeSample(_ data: Data, format: CMFormatDescription, sampleCount: Int,
                                   timing: CMSampleTimingInfo) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: data.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
            let block
        else { return nil }

        let copied = data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }

        var timing = timing
        var sample: CMSampleBuffer?
        let isAudio = CMFormatDescriptionGetMediaType(format) == kCMMediaType_Audio
        var size = isAudio ? PCM.bytesPerFrame : data.count
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: sampleCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        return status == noErr ? sample : nil
    }
}
