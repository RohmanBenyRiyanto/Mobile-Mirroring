import Compression
import Foundation

public struct HTTPHeader: Equatable, Hashable, Sendable {
    public let name: String
    public let value: String
    public init(name: String, value: String) { self.name = name; self.value = value }
}

/// Reads the parts of an HTTP/1.1 message the API log shows: headers, status line and a readable body.
public enum HTTPMessage {
    public static let bodyCapture = 64 << 10

    /// Splits a captured message at the blank line that ends its head.
    public static func split(_ data: Data) -> (head: String, body: Data)? {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        return (String(decoding: data[..<range.lowerBound], as: UTF8.self), data[range.upperBound...])
    }

    /// Header lines after the first (request or status) line.
    public static func headers(inHead head: String) -> [HTTPHeader] {
        head.components(separatedBy: "\r\n").dropFirst().compactMap { line in
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return nil }
            return HTTPHeader(name: String(line[..<colon]), value: line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
    }

    public static func firstLine(of head: String) -> String { head.components(separatedBy: "\r\n").first ?? "" }

    public static func value(of name: String, in headers: [HTTPHeader]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The body as it was sent: chunked framing removed, and gzip or deflate undone.
    public static func decodedBody(_ raw: Data, headers: [HTTPHeader]) -> Data {
        var body = raw
        if value(of: "Transfer-Encoding", in: headers)?.localizedCaseInsensitiveContains("chunked") == true, let plain = dechunk(body) { body = plain }
        switch value(of: "Content-Encoding", in: headers)?.lowercased() {
        case "gzip": body = inflate(gzip: body) ?? body
        case "deflate": body = (try? (body as NSData).decompressed(using: .zlib) as Data) ?? body
        default: break
        }
        return body
    }

    public enum Preview: Equatable {
        case empty
        case text(String, truncated: Bool)
        case binary(bytes: Int, type: String?)
    }

    /// A body worth showing: text (JSON pretty-printed) or a note that it is binary.
    public static func preview(of raw: Data, headers: [HTTPHeader], truncated: Bool = false) -> Preview {
        guard !raw.isEmpty else { return .empty }
        let body = decodedBody(raw, headers: headers)
        let type = value(of: "Content-Type", in: headers)
        guard !body.isEmpty else { return .empty }
        guard let text = String(data: body, encoding: .utf8), !text.unicodeScalars.contains(where: { $0.value < 9 || ($0.value > 13 && $0.value < 32) }) else {
            return .binary(bytes: body.count, type: type)
        }
        if type?.localizedCaseInsensitiveContains("json") == true || text.hasPrefix("{") || text.hasPrefix("["),
           let object = try? JSONSerialization.jsonObject(with: body), let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            return .text(String(decoding: pretty, as: UTF8.self), truncated: truncated)
        }
        return .text(text, truncated: truncated)
    }

    /// A curl command that repeats the request. Values are single-quoted for the shell.
    public static func curl(method: String, url: String, headers: [HTTPHeader], body: Data) -> String {
        func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var parts = ["curl", "-X", method, quote(url)]
        for header in headers where !["host", "content-length", "connection", "accept-encoding"].contains(header.name.lowercased()) {
            parts += ["-H", quote("\(header.name): \(header.value)")]
        }
        if !body.isEmpty, let text = String(data: body, encoding: .utf8) { parts += ["--data-raw", quote(text)] }
        return parts.joined(separator: " ")
    }

    static func dechunk(_ data: Data) -> Data? {
        var result = Data(), index = data.startIndex
        while index < data.endIndex {
            guard let lineEnd = data[index...].range(of: Data("\r\n".utf8)) else { return result.isEmpty ? nil : result }
            let sizeText = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self).split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { return result.isEmpty ? nil : result }
            if size == 0 { return result }
            let start = lineEnd.upperBound
            let end = min(start + size, data.endIndex)
            result.append(data[start..<end])
            index = min(end + 2, data.endIndex)
        }
        return result
    }

    static func inflate(gzip data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var offset = 10
        if flags & 4 != 0 { guard offset + 2 <= bytes.count else { return nil }; offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8 }
        for bit in [UInt8(8), 16] where flags & bit != 0 { while offset < bytes.count, bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 2 != 0 { offset += 2 }
        guard offset < bytes.count - 8 else { return nil }
        let deflated = Data(bytes[offset..<(bytes.count - 8)])
        return try? (deflated as NSData).decompressed(using: .zlib) as Data
    }
}
