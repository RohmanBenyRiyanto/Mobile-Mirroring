import DomainModels
import Foundation

/// A small HTTP proxy on the loopback interface that the phone reaches through `adb reverse`.
/// It forwards plain HTTP and HTTPS tunnels and reports each call. HTTPS contents are never opened: only the host is known.
public final class LoggingProxy: @unchecked Sendable {
    public struct Report: Sendable {
        public var id: Int
        public var request: ProxyRequest
        public var startedAt: Date
        public var status: Int?
        public var durationMillis: Int?
        public var sent = 0
        public var received = 0
        public var details: APICallDetails?
    }

    private static let maxConnections = 64

    public let port: UInt16
    private let listener: LoopbackListener
    private let isRunning = LockedValue(true)
    private let active = LockedValue<[ObjectIdentifier: TCPStream]>([:])
    private let nextID = LockedValue(0)
    private let onReport: @Sendable (Report) -> Void
    private let profile = LockedValue(NetworkProfile.unlimited)

    /// Slows every call from now on (a call already running picks up the new speed on its next chunk).
    public func setProfile(_ new: NetworkProfile) { profile.set(new) }

    /// `onReport` is called once when a call starts (no duration yet) and once when it ends.
    public init(port: UInt16 = 0, onReport: @escaping @Sendable (Report) -> Void) throws {
        listener = try LoopbackListener(port: port)
        self.port = listener.port
        self.onReport = onReport
    }

    public func start() {
        let thread = Thread { [self] in
            while isRunning.get() {
                guard let client = try? listener.accept(timeout: 0.5, shouldContinue: { isRunning.get() }) else { continue }
                if active.get().count >= Self.maxConnections { client.shutdown(); continue }
                let key = ObjectIdentifier(client)
                active.withLock { $0[key] = client }
                DispatchQueue.global(qos: .utility).async { [self] in
                    handle(client)
                    client.shutdown()
                    active.withLock { _ = $0.removeValue(forKey: key) }
                }
            }
        }
        thread.name = "benzmirror.proxy.accept"
        thread.start()
    }

    public func stop() {
        isRunning.set(false)
        active.withLock { all in all.values.forEach { $0.shutdown() }; all.removeAll() }
    }

    // MARK: One connection

    private func handle(_ client: TCPStream) {
        client.setTimeouts(seconds: 120)
        var buffer = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while buffer.range(of: terminator) == nil {
            guard buffer.count <= ProxyRequestParser.maxHeadBytes, let chunk = try? client.readSome(limit: 4096), !chunk.isEmpty else { return }
            buffer.append(chunk)
        }
        let split = buffer.range(of: terminator)!.upperBound
        guard let request = ProxyRequestParser.parse(buffer.prefix(split)) else {
            _ = try? client.write(Data("HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8))
            return
        }
        let leftover = buffer.suffix(from: split)
        let id = nextID.withLock { value -> Int in value += 1; return value }
        let started = Date()
        var report = Report(id: id, request: request, startedAt: started)
        onReport(report)

        let latency = profile.get().latencyMillis
        if latency > 0 { Thread.sleep(forTimeInterval: Double(latency) / 1000) }
        guard let server = try? TCPStream.connect(host: request.host, port: request.port) else {
            _ = try? client.write(Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8))
            report.status = 502
            report.durationMillis = Int(Date().timeIntervalSince(started) * 1000)
            onReport(report)
            return
        }
        server.setTimeouts(seconds: 120)
        let key = ObjectIdentifier(server)
        active.withLock { $0[key] = server }
        defer { server.shutdown(); active.withLock { _ = $0.removeValue(forKey: key) } }

        let sent = LockedValue(0), received = LockedValue(0)
        let limits = profile
        let firstBytes = LockedValue(Data())
        // Plain HTTP is kept for the log's detail view (cut at a size limit); a tunnel's contents are encrypted and are not.
        let requestCapture = LockedValue(Data(leftover.prefix(HTTPMessage.bodyCapture)))
        let responseCapture = LockedValue(Data())
        do {
            if request.isTunnel {
                try client.write(Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8))
                if !leftover.isEmpty { try server.write(leftover); sent.withLock { $0 += leftover.count } }
            } else {
                try server.write(request.forwardedHead)
                sent.withLock { $0 += request.forwardedHead.count }
                if !leftover.isEmpty { try server.write(leftover); sent.withLock { $0 += leftover.count } }
            }
        } catch { return }

        // Client to server runs on its own thread; the call ends when the server side closes.
        Thread.detachNewThread {
            while let chunk = try? client.readSome(limit: 16 << 10), !chunk.isEmpty {
                let wait = NetworkProfile.transferDelay(bytes: chunk.count, kbps: limits.get().upKbps)
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                if (try? server.write(chunk)) == nil { break }
                if !request.isTunnel { requestCapture.withLock { if $0.count < HTTPMessage.bodyCapture { $0.append(chunk.prefix(HTTPMessage.bodyCapture - $0.count)) } } }
                sent.withLock { $0 += chunk.count }
            }
        }
        while let chunk = try? server.readSome(limit: 16 << 10), !chunk.isEmpty {
            if !request.isTunnel {
                firstBytes.withLock { if $0.count < 32 { $0.append(chunk.prefix(32 - $0.count)) } }
                responseCapture.withLock { if $0.count < HTTPMessage.bodyCapture + ProxyRequestParser.maxHeadBytes { $0.append(chunk.prefix(HTTPMessage.bodyCapture + ProxyRequestParser.maxHeadBytes - $0.count)) } }
            }
            let wait = NetworkProfile.transferDelay(bytes: chunk.count, kbps: limits.get().downKbps)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            if (try? client.write(chunk)) == nil { break }
            received.withLock { $0 += chunk.count }
        }
        report.status = request.isTunnel ? nil : ProxyRequestParser.status(fromResponse: firstBytes.get())
        report.durationMillis = Int(Date().timeIntervalSince(started) * 1000)
        report.sent = sent.get()
        report.received = received.get()
        if !request.isTunnel { report.details = Self.details(request: request, requestBody: requestCapture.get(), response: responseCapture.get(), totalSent: report.sent, totalReceived: report.received) }
        onReport(report)
    }

    private static func details(request: ProxyRequest, requestBody: Data, response: Data, totalSent: Int, totalReceived: Int) -> APICallDetails {
        var details = APICallDetails()
        details.requestHeaders = HTTPMessage.headers(inHead: request.originalHead)
        details.requestBody = requestBody
        details.requestBodyTruncated = totalSent - request.forwardedHead.count > requestBody.count
        if let (head, body) = HTTPMessage.split(response) {
            details.statusLine = HTTPMessage.firstLine(of: head)
            details.responseHeaders = HTTPMessage.headers(inHead: head)
            details.responseBody = body
            details.responseBodyTruncated = totalReceived - (response.count - body.count) > body.count
        } else {
            details.statusLine = HTTPMessage.firstLine(of: String(decoding: response.prefix(200), as: UTF8.self))
        }
        return details
    }
}
