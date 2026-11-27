import XCTest
@testable import DomainModels

final class APICallTests: XCTestCase {
    private func head(_ text: String) -> Data { Data(text.utf8) }

    func testPlainRequestIsRewrittenForTheServer() throws {
        let request = try XCTUnwrap(ProxyRequestParser.parse(head("GET http://example.com:8080/a/b?x=1 HTTP/1.1\r\nHost: example.com:8080\r\nProxy-Connection: keep-alive\r\nConnection: keep-alive\r\nAccept: */*\r\n\r\n")))
        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.port, 8080)
        XCTAssertFalse(request.isTunnel)
        let forwarded = String(decoding: request.forwardedHead, as: UTF8.self)
        XCTAssertTrue(forwarded.hasPrefix("GET /a/b?x=1 HTTP/1.1\r\n"))
        XCTAssertFalse(forwarded.lowercased().contains("proxy-connection"))
        XCTAssertTrue(forwarded.hasSuffix("Accept: */*\r\nConnection: close\r\n\r\n"))
    }

    func testConnectUsesTheHostAndDefaultsToTLSPort() throws {
        let tunnel = try XCTUnwrap(ProxyRequestParser.parse(head("CONNECT api.example.com:443 HTTP/1.1\r\nHost: api.example.com:443\r\n\r\n")))
        XCTAssertTrue(tunnel.isTunnel)
        XCTAssertEqual(tunnel.url, "api.example.com:443")
        XCTAssertEqual(ProxyRequestParser.parse(head("CONNECT example.com HTTP/1.1\r\n\r\n"))?.port, 443)
    }

    func testRefusesNonsense() {
        XCTAssertNil(ProxyRequestParser.parse(head("GET / HTTP/1.1\r\n\r\n")))
        XCTAssertNil(ProxyRequestParser.parse(head("GET ftp://x/ HTTP/1.1\r\n\r\n")))
        XCTAssertNil(ProxyRequestParser.parse(head("CONNECT bad host:1 HTTP/1.1\r\n\r\n")))
        XCTAssertNil(ProxyRequestParser.parse(head("CONNECT a.com:99999 HTTP/1.1\r\n\r\n")))
        XCTAssertNil(ProxyRequestParser.parse(Data(count: ProxyRequestParser.maxHeadBytes + 1)))
    }

    func testStatusLine() {
        XCTAssertEqual(ProxyRequestParser.status(fromResponse: head("HTTP/1.1 404 Not Found\r\nA: b")), 404)
        XCTAssertNil(ProxyRequestParser.status(fromResponse: head("garbage")))
    }

    func testLogFinishesCapsAndExports() {
        var log = APICallLog()
        for i in 0..<(APICallLog.capacity + 5) { log.begin(APICall(id: i, startedAt: Date(timeIntervalSince1970: 0), method: "GET", host: "h", url: "http://h/\(i)", isTunnel: false)) }
        XCTAssertEqual(log.calls.count, APICallLog.capacity)
        let last = APICallLog.capacity + 4
        log.finish(id: last, status: 500, durationMillis: 12, sent: 1, received: 2)
        XCTAssertTrue(log.calls.last?.isError == true)
        XCTAssertTrue(log.csv().contains(",500,12,1,2"))
        log.clear()
        XCTAssertTrue(log.calls.isEmpty)
    }
}
