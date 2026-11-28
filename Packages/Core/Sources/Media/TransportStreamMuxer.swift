import Foundation
import DomainModels

public struct TransportStreamMuxer {
    public static let packetSize = 188
    public static let videoPID: UInt16 = 0x100
    public static let audioPID: UInt16 = 0x101
    public static let pmtPID: UInt16 = 0x1000

    private static let pcrLead: UInt64 = 9_000
    private static let timestampMask: UInt64 = (1 << 33) - 1

    private let codec: VideoCodec
    public var includesAudio: Bool
    private var continuity: [UInt16: UInt8] = [:]

    public init(codec: VideoCodec, includesAudio: Bool) {
        self.codec = codec
        self.includesAudio = includesAudio
    }

    public static func ticks(microseconds: Int64) -> UInt64 {
        UInt64(max(microseconds, 0)) * 9 / 100
    }

    // MARK: Tables

    public mutating func tables() -> Data {
        psiPacket(pid: 0, section: programAssociationSection()) + psiPacket(pid: Self.pmtPID, section: programMapSection())
    }

    private func programAssociationSection() -> Data {
        var section = Data([0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01])
        section.append(contentsOf: [0xE0 | UInt8(Self.pmtPID >> 8), UInt8(Self.pmtPID & 0xFF)])
        section.appendBigEndian(Self.crc32(section))
        return section
    }

    private func programMapSection() -> Data {
        var body = Data([0x00, 0x01, 0xC1, 0x00, 0x00])
        body.append(contentsOf: [0xE0 | UInt8(Self.videoPID >> 8), UInt8(Self.videoPID & 0xFF)])
        body.append(contentsOf: [0xF0, 0x00])
        body.append(streamEntry(type: codec == .h264 ? 0x1B : 0x24, pid: Self.videoPID))
        if includesAudio { body.append(streamEntry(type: 0x0F, pid: Self.audioPID)) }

        let length = body.count + 4
        var section = Data([0x02, 0xB0 | UInt8((length >> 8) & 0x0F), UInt8(length & 0xFF)])
        section.append(body)
        section.appendBigEndian(Self.crc32(section))
        return section
    }

    private func streamEntry(type: UInt8, pid: UInt16) -> Data {
        Data([type, 0xE0 | UInt8(pid >> 8), UInt8(pid & 0xFF), 0xF0, 0x00])
    }

    // MARK: Elementary streams

    public mutating func video(_ accessUnit: Data, ticks: UInt64, isKeyFrame: Bool) -> Data {
        let pes = Self.pes(streamID: 0xE0, payload: accessUnit, ticks: ticks, boundedLength: false)
        let pcr = (ticks &+ Self.timestampMask + 1 &- Self.pcrLead) & Self.timestampMask
        return packetize(pid: Self.videoPID, pes: pes, pcr: pcr, randomAccess: isKeyFrame)
    }

    public mutating func audio(_ adtsFrame: Data, ticks: UInt64) -> Data {
        let pes = Self.pes(streamID: 0xC0, payload: adtsFrame, ticks: ticks, boundedLength: true)
        return packetize(pid: Self.audioPID, pes: pes, pcr: nil, randomAccess: false)
    }

    // MARK: Packetization

    private mutating func psiPacket(pid: UInt16, section: Data) -> Data {
        var packet = header(pid: pid, startsPayload: true, adaptation: false, payload: true)
        packet.append(0x00)
        packet.append(section)
        packet.append(Data(repeating: 0xFF, count: Self.packetSize - packet.count))
        return packet
    }

    private mutating func packetize(pid: UInt16, pes: Data, pcr: UInt64?, randomAccess: Bool) -> Data {
        var output = Data(capacity: (pes.count / 184 + 2) * Self.packetSize)
        var offset = 0

        while offset < pes.count {
            let isFirst = offset == 0
            var field = isFirst ? Self.firstAdaptationContent(pcr: pcr, randomAccess: randomAccess) : Data()

            let overhead = field.isEmpty ? 0 : 1 + field.count
            let chunk = min(pes.count - offset, 184 - overhead)
            let stuffing = 184 - overhead - chunk
            if stuffing > 0 {
                if field.isEmpty {
                    field = stuffing == 1 ? Data() : Data([0x00]) + Data(repeating: 0xFF, count: stuffing - 2)
                } else {
                    field.append(Data(repeating: 0xFF, count: stuffing))
                }
            }

            let hasAdaptation = stuffing > 0 || !field.isEmpty
            output.append(header(pid: pid, startsPayload: isFirst, adaptation: hasAdaptation, payload: true))
            if hasAdaptation {
                output.append(UInt8(field.count))
                output.append(field)
            }
            output.append(pes.subdata(in: offset..<offset + chunk))
            offset += chunk
        }
        return output
    }

    private static func firstAdaptationContent(pcr: UInt64?, randomAccess: Bool) -> Data {
        guard pcr != nil || randomAccess else { return Data() }
        var content = Data([(randomAccess ? 0x40 : 0) | (pcr != nil ? 0x10 : 0)])
        if let pcr { content.append(pcrBytes(pcr)) }
        return content
    }

    private mutating func header(pid: UInt16, startsPayload: Bool, adaptation: Bool, payload: Bool) -> Data {
        let counter = continuity[pid, default: 0]
        if payload { continuity[pid] = (counter + 1) & 0x0F }
        let control: UInt8 = (adaptation ? 0x20 : 0) | (payload ? 0x10 : 0)
        return Data([0x47, (startsPayload ? 0x40 : 0) | UInt8(pid >> 8), UInt8(pid & 0xFF), control | counter])
    }

    // MARK: Encodings

    public static func pes(streamID: UInt8, payload: Data, ticks: UInt64, boundedLength: Bool) -> Data {
        var pes = Data([0x00, 0x00, 0x01, streamID])
        pes.appendBigEndian(boundedLength ? UInt16(clamping: payload.count + 8) : 0)
        pes.append(contentsOf: [0x80, 0x80, 0x05])
        pes.append(timestampBytes(ticks & timestampMask))
        pes.append(payload)
        return pes
    }

    public static func timestampBytes(_ value: UInt64) -> Data {
        Data([UInt8(0x21 | ((value >> 29) & 0x0E)),
              UInt8((value >> 22) & 0xFF),
              UInt8(0x01 | ((value >> 14) & 0xFE)),
              UInt8((value >> 7) & 0xFF),
              UInt8(0x01 | ((value << 1) & 0xFE))])
    }

    public static func pcrBytes(_ base: UInt64) -> Data {
        Data([UInt8((base >> 25) & 0xFF),
              UInt8((base >> 17) & 0xFF),
              UInt8((base >> 9) & 0xFF),
              UInt8((base >> 1) & 0xFF),
              UInt8(((base & 1) << 7) | 0x7E),
              0x00])
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 { crc = crc & 0x8000_0000 != 0 ? (crc << 1) ^ 0x04C1_1DB7 : crc << 1 }
        }
        return crc
    }
}
