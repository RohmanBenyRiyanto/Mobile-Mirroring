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

final class HTTPMessageTests: XCTestCase {
    func testHeadersStatusAndJSONPreview() {
        let message = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nSet-Cookie: a=b\r\n\r\n{\"b\":1,\"a\":[1,2]}".utf8)
        let (head, body) = HTTPMessage.split(message)!
        XCTAssertEqual(HTTPMessage.firstLine(of: head), "HTTP/1.1 200 OK")
        let headers = HTTPMessage.headers(inHead: head)
        XCTAssertEqual(headers.map(\.name), ["Content-Type", "Set-Cookie"])
        guard case let .text(text, _) = HTTPMessage.preview(of: body, headers: headers) else { return XCTFail("expected text") }
        XCTAssertTrue(text.contains("\"a\" : [") && text.contains("\n"), "JSON is pretty-printed with sorted keys")
    }

    func testChunkedBodiesAreJoinedAndBinaryIsNotShownAsText() {
        let chunked = Data("5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n".utf8)
        let headers = [HTTPHeader(name: "Transfer-Encoding", value: "chunked")]
        XCTAssertEqual(String(decoding: HTTPMessage.decodedBody(chunked, headers: headers), as: UTF8.self), "hello world")
        XCTAssertEqual(HTTPMessage.preview(of: Data([0, 1, 2, 255]), headers: [HTTPHeader(name: "Content-Type", value: "image/png")]), .binary(bytes: 4, type: "image/png"))
        XCTAssertEqual(HTTPMessage.preview(of: Data(), headers: []), .empty)
    }

    func testGzipBodiesAreInflated() throws {
        let gzip = Data(base64Encoded: "H4sIAAAAAAAAA8tIzcnJVyjPL8pJAQCFEUoNCwAAAA==")!
        XCTAssertEqual(String(decoding: HTTPMessage.decodedBody(gzip, headers: [HTTPHeader(name: "Content-Encoding", value: "gzip")]), as: UTF8.self), "hello world")
    }

    func testCurlQuotesEverything() {
        let curl = HTTPMessage.curl(method: "POST", url: "http://x/it's", headers: [HTTPHeader(name: "Host", value: "x"), HTTPHeader(name: "A", value: "b")], body: Data("d".utf8))
        XCTAssertEqual(curl, "curl -X POST 'http://x/it'\\''s' -H 'A: b' --data-raw 'd'")
    }
}
