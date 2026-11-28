import Foundation

/// The first line and headers of a request that reached the logging proxy.
public struct ProxyRequest: Equatable, Sendable {
    public var method: String
    public var host: String
    public var port: Int
    /// Full address for plain HTTP; "host:port" for a tunnel.
    public var url: String
    public var isTunnel: Bool
    /// The request head to send on to the server: origin-form path, no proxy headers, connection closed after one answer.
    public var forwardedHead: Data
    /// The head exactly as the phone sent it, for the log's header view.
    public var originalHead: String
}

public enum ProxyRequestParser {
    public static let maxHeadBytes = 16 << 10

    public static func parse(_ head: Data) -> ProxyRequest? {
        guard head.count <= maxHeadBytes, let text = String(data: head, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/"), parts[0].allSatisfy({ $0.isLetter }) else { return nil }
        let method = parts[0].uppercased()

        if method == "CONNECT" {
            guard let (host, port) = hostAndPort(parts[1], defaultPort: 443) else { return nil }
            return ProxyRequest(method: method, host: host, port: port, url: "\(host):\(port)", isTunnel: true, forwardedHead: Data(), originalHead: text)
        }
        guard let url = URL(string: parts[1]), let scheme = url.scheme?.lowercased(), scheme == "http", let host = url.host, !host.isEmpty else { return nil }
        let port = url.port ?? 80
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query { path += "?" + query }

        var rebuilt = ["\(method) \(path) \(parts[2])"]
        for line in lines.dropFirst() where !line.isEmpty {
            let name = line.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
            if ["proxy-connection", "connection", "proxy-authorization", "keep-alive"].contains(name) { continue }
            rebuilt.append(line)
        }
        rebuilt.append("Connection: close")
        let forwarded = rebuilt.joined(separator: "\r\n") + "\r\n\r\n"
        return ProxyRequest(method: method, host: host, port: port, url: parts[1], isTunnel: false, forwardedHead: Data(forwarded.utf8), originalHead: text)
    }

    public static func status(fromResponse bytes: Data) -> Int? {
        guard let line = String(decoding: bytes.prefix(32), as: UTF8.self).split(separator: "\r\n").first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/") else { return nil }
        return Int(parts[1])
    }

    private static func hostAndPort(_ text: String, defaultPort: Int) -> (String, Int)? {
        let pieces = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let host = pieces.first, !host.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || "-._".contains($0) }) else { return nil }
        if pieces.count == 1 { return (host, defaultPort) }
        guard pieces.count == 2, let port = Int(pieces[1]), (1...65535).contains(port) else { return nil }
        return (host, port)
    }
}

/// What was seen of one call, kept small: heads in full, bodies cut at `HTTPMessage.bodyCapture`.
public struct APICallDetails: Equatable, Sendable {
    public var requestHeaders: [HTTPHeader] = []
    public var responseHeaders: [HTTPHeader] = []
    public var statusLine = ""
    public var requestBody = Data()
    public var responseBody = Data()
    public var requestBodyTruncated = false
    public var responseBodyTruncated = false
    public init() {}
}

public struct APICall: Identifiable, Equatable, Sendable {
    public let id: Int
    public var startedAt: Date
    public var method: String
    public var host: String
    public var url: String
    public var isTunnel: Bool
    public var status: Int?
    public var durationMillis: Int?
    public var sentBytes = 0
    public var receivedBytes = 0
    public var details: APICallDetails?

    public init(id: Int, startedAt: Date, method: String, host: String, url: String, isTunnel: Bool) {
        self.id = id
        self.startedAt = startedAt
        self.method = method
        self.host = host
        self.url = url
        self.isTunnel = isTunnel
    }

    public var isFinished: Bool { durationMillis != nil }
    public var isError: Bool { (status ?? 0) >= 400 }
}

/// Newest calls last, capped so a chatty app cannot grow it without bound.
public struct APICallLog: Equatable, Sendable {
    public static let capacity = 500
    public private(set) var calls: [APICall] = []

    public init() {}

    public mutating func begin(_ call: APICall) {
        calls.append(call)
        if calls.count > Self.capacity { calls.removeFirst(calls.count - Self.capacity) }
    }

    public mutating func finish(id: Int, status: Int?, durationMillis: Int, sent: Int, received: Int, details: APICallDetails? = nil) {
        guard let index = calls.lastIndex(where: { $0.id == id }) else { return }
        calls[index].status = status
        calls[index].durationMillis = durationMillis
        calls[index].sentBytes = sent
        calls[index].receivedBytes = received
        calls[index].details = details
    }

    public mutating func clear() { calls.removeAll() }

    public func csv() -> String {
        func cell(_ text: String) -> String { text.contains(where: { ",\"\n".contains($0) }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text }
        var rows = ["time,method,url,status,duration_ms,sent_bytes,received_bytes"]
        let formatter = ISO8601DateFormatter()
        for c in calls {
            rows.append([formatter.string(from: c.startedAt), c.method, cell(c.url), c.status.map(String.init) ?? "", c.durationMillis.map(String.init) ?? "", String(c.sentBytes), String(c.receivedBytes)].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
