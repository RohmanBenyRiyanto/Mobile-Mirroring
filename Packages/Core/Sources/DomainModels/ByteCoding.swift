import Foundation

extension Data {
    public mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    public func readBigEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        precondition(offset >= 0 && offset + MemoryLayout<T>.size <= count, "read out of bounds")
        return withUnsafeBytes { T(bigEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
    }
}

extension String {
    public func utf8Prefix(maxBytes: Int) -> Data {
        var result = Data()
        for character in self {
            let bytes = Data(String(character).utf8)
            if result.count + bytes.count > maxBytes { break }
            result.append(bytes)
        }
        return result
    }
}
