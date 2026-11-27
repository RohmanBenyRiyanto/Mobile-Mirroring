import Foundation

/// Helpers for H.264/H.265 byte streams in Annex-B form (`00 00 01` start codes),
/// which is what the Android encoder produces, and conversion to the length-prefixed
/// (AVCC/HVCC) form that VideoToolbox expects.
public enum AnnexB {
    /// Byte ranges of the NAL units in `bytes`, without start codes or trailing zero padding.
    public static func nalUnitRanges(in bytes: UnsafeRawBufferPointer) -> [Range<Int>] {
        var starts: [Int] = []
        var index = 0
        while index + 3 <= bytes.count {
            if bytes[index + 2] > 1 {
                index += 3 // cannot be inside a start code, skip ahead
            } else if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                starts.append(index + 3)
                index += 3
            } else {
                index += 1
            }
        }

        return starts.enumerated().compactMap { position, start in
            var end = position + 1 < starts.count ? starts[position + 1] - 3 : bytes.count
            while end > start, bytes[end - 1] == 0 { end -= 1 } // zero_byte of a 4-byte start code
            return end > start ? start..<end : nil
        }
    }

    /// Splits `data` into NAL units (each copied, header byte included).
    public static func nalUnits(in data: Data) -> [Data] {
        data.withUnsafeBytes { buffer in
            nalUnitRanges(in: buffer).map { Data(buffer[$0]) }
        }
    }

    /// Re-wraps `data` as 4-byte-length-prefixed NAL units, dropping those for which
    /// `isExcluded(firstByte)` is true (parameter sets and delimiters travel in the format description).
    public static func lengthPrefixed(_ data: Data, excluding isExcluded: (UInt8) -> Bool) -> Data {
        data.withUnsafeBytes { buffer in
            var output = Data(capacity: buffer.count + 16)
            for range in nalUnitRanges(in: buffer) where !isExcluded(buffer[range.lowerBound]) {
                output.appendBigEndian(UInt32(range.count))
                output.append(contentsOf: UnsafeRawBufferPointer(rebasing: buffer[range]))
            }
            return output
        }
    }
}
