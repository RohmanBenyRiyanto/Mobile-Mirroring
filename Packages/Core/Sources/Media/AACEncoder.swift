import AVFoundation

/// Encodes the phone's 48 kHz 16-bit stereo PCM to AAC-LC and wraps each frame in an ADTS header,
/// the form MPEG transport streams carry.
public final class AACEncoder {
    public static let framesPerPacket = 1_024
    public static let bitRate = 128_000

    /// One encoded frame and the time of its first sample, in microseconds on the device clock.
    public struct Frame {
        public let adts: Data
        public let presentationTime: Int64

    public init(adts: Data, presentationTime: Int64) {
        self.adts = adts
        self.presentationTime = presentationTime
    }
    }

    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private var pending = Data()
    /// Device time of the first sample ever received; frame times count from here.
    private var anchor: Int64?
    private var blocksEncoded: Int64 = 0

    public init?() {
        guard let input = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: SampleBuffers.PCM.sampleRate,
                                        channels: 2, interleaved: true),
              let output = AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                    AVSampleRateKey: SampleBuffers.PCM.sampleRate,
                                                    AVNumberOfChannelsKey: 2,
                                                    AVEncoderBitRateKey: Self.bitRate]),
              let converter = AVAudioConverter(from: input, to: output)
        else { return nil }
        inputFormat = input
        self.converter = converter
    }

    /// Feeds PCM; returns every AAC frame that is now complete. Timestamps follow the sample count,
    /// so they stay smooth even when packets arrive in uneven bursts.
    public func encode(_ pcm: Data, presentationTime: Int64) -> [Frame] {
        let anchor = self.anchor ?? presentationTime
        self.anchor = anchor
        pending.append(pcm.prefix(pcm.count / SampleBuffers.PCM.bytesPerFrame * SampleBuffers.PCM.bytesPerFrame))

        let blockBytes = Self.framesPerPacket * SampleBuffers.PCM.bytesPerFrame
        var frames: [Frame] = []
        while pending.count >= blockBytes {
            let block = Data(pending.prefix(blockBytes))
            pending = Data(pending.dropFirst(blockBytes))
            let time = anchor + blocksEncoded * Int64(Self.framesPerPacket) * 1_000_000 / Int64(SampleBuffers.PCM.sampleRate)
            blocksEncoded += 1
            if let adts = encodeBlock(block) { frames.append(Frame(adts: adts, presentationTime: time)) }
        }
        return frames
    }

    private func encodeBlock(_ block: Data) -> Data? {
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(Self.framesPerPacket)),
              let channel = input.int16ChannelData
        else { return nil }
        input.frameLength = AVAudioFrameCount(Self.framesPerPacket)
        _ = block.withUnsafeBytes { memcpy(channel[0], $0.baseAddress!, block.count) }

        let output = AVAudioCompressedBuffer(format: converter.outputFormat, packetCapacity: 1,
                                             maximumPacketSize: converter.maximumOutputPacketSize)
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        // The encoder needs one block of priming before it emits its first packet.
        guard error == nil, output.packetCount > 0, let descriptions = output.packetDescriptions else { return nil }

        let payload = Data(bytes: output.data, count: Int(descriptions[0].mDataByteSize))
        return Self.adtsHeader(payloadLength: payload.count) + payload
    }

    /// 7-byte ADTS header: AAC-LC, 48 kHz, stereo, no CRC.
    public static func adtsHeader(payloadLength: Int) -> Data {
        let length = payloadLength + 7
        return Data([0xFF, 0xF1,
                     0x4C, // profile LC (1), sample-rate index 3 (48 kHz), channel config high bit 0
                     UInt8(0x80 | ((length >> 11) & 0x03)), // channel config low bits 10 (stereo)
                     UInt8((length >> 3) & 0xFF),
                     UInt8(((length & 0x07) << 5) | 0x1F),
                     0xFC])
    }
}
