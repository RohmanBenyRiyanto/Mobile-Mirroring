import XCTest
import DomainModels
@testable import Networking

final class LoggingProxyTests: XCTestCase {
    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [LoggingProxy.Report] = []
        func add(_ r: LoggingProxy.Report) { lock.withLock { items.append(r) } }
        var all: [LoggingProxy.Report] { lock.withLock { items } }
    }

    /// A one-shot upstream: reads the request head, answers, and closes.
    private func upstream(answer: @escaping @Sendable (Data) -> Data) throws -> (LoopbackListener, Thread) {
        let listener = try LoopbackListener()
        let thread = Thread {
            guard let stream = try? listener.accept(timeout: 5) else { return }
            var head = Data()
            while head.range(of: Data("\r\n\r\n".utf8)) == nil, let chunk = try? stream.readSome(limit: 4096), !chunk.isEmpty { head.append(chunk) }
            try? stream.write(answer(head))
            stream.shutdown()
        }
        thread.start()
        return (listener, thread)
    }

    func testForwardsPlainHTTPAndReportsStatusAndSizes() throws {
        let seen = LockedValue(Data())
        let (server, _) = try upstream { head in seen.set(head); return Data("HTTP/1.1 201 Created\r\nContent-Length: 2\r\n\r\nok".utf8) }
        let reports = Reports()
        let proxy = try LoggingProxy { reports.add($0) }
        proxy.start()
        defer { proxy.stop() }

        let client = try TCPStream.connect(host: "127.0.0.1", port: Int(proxy.port))
        client.setTimeouts(seconds: 5)
        try client.write(Data("GET http://127.0.0.1:\(server.port)/path?q=1 HTTP/1.1\r\nHost: 127.0.0.1\r\nProxy-Connection: keep-alive\r\n\r\n".utf8))
        var response = Data()
        while let chunk = try? client.readSome(limit: 4096), !chunk.isEmpty { response.append(chunk) }

        XCTAssertTrue(String(decoding: response, as: UTF8.self).hasSuffix("ok"))
        XCTAssertTrue(String(decoding: seen.get(), as: UTF8.self).hasPrefix("GET /path?q=1 HTTP/1.1"))
        let deadline = Date().addingTimeInterval(3)
        while reports.all.last?.durationMillis == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        let last = try XCTUnwrap(reports.all.last)
        XCTAssertEqual(last.status, 201)
        XCTAssertGreaterThan(last.received, 0)
        XCTAssertEqual(reports.all.count, 2)
    }

    func testConnectTunnelsBytesBothWays() throws {
        let server = try LoopbackListener()
        Thread {
            guard let stream = try? server.accept(timeout: 5) else { return }
            if let data = try? stream.readSome(limit: 64), !data.isEmpty { try? stream.write(Data("echo:".utf8) + data) }
            stream.shutdown()
        }.start()
        let reports = Reports()
        let proxy = try LoggingProxy { reports.add($0) }
        proxy.start()
        defer { proxy.stop() }

        let client = try TCPStream.connect(host: "127.0.0.1", port: Int(proxy.port))
        client.setTimeouts(seconds: 5)
        try client.write(Data("CONNECT 127.0.0.1:\(server.port) HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
        let established = try client.readSome(limit: 4096)
        XCTAssertTrue(String(decoding: established, as: UTF8.self).contains("200 Connection Established"))
        try client.write(Data("ping".utf8))
        var answer = Data()
        while let chunk = try? client.readSome(limit: 64), !chunk.isEmpty { answer.append(chunk) }
        XCTAssertEqual(String(decoding: answer, as: UTF8.self), "echo:ping")
        let deadline = Date().addingTimeInterval(3)
        while reports.all.last?.durationMillis == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(reports.all.last?.request.isTunnel == true)
        XCTAssertNil(reports.all.last?.status)
    }

    func testBadRequestAndUnreachableHostGetErrors() throws {
        let proxy = try LoggingProxy { _ in }
        proxy.start()
        defer { proxy.stop() }
        let bad = try TCPStream.connect(host: "127.0.0.1", port: Int(proxy.port))
        bad.setTimeouts(seconds: 5)
        try bad.write(Data("nonsense\r\n\r\n".utf8))
        XCTAssertTrue(String(decoding: try bad.readSome(limit: 200), as: UTF8.self).contains("400"))

        let closed = try LoopbackListener()
        let port = closed.port
        let unreachable = try TCPStream.connect(host: "127.0.0.1", port: Int(proxy.port))
        unreachable.setTimeouts(seconds: 5)
        withExtendedLifetime(closed) {}
        try unreachable.write(Data("GET http://127.0.0.1:1/ HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
        _ = port
        XCTAssertTrue(String(decoding: try unreachable.readSome(limit: 200), as: UTF8.self).contains("502"))
    }
}
