import XCTest
@testable import DomainModels

final class InspectionAssemblerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testAnHTTPSCallIsPutTogetherWithItsContents() throws {
        var assembler = InspectionAssembler(clock: { Date(timeIntervalSince1970: 1000.25) })
        let start = try XCTUnwrap(assembler.apply(.requestStarted(id: 7, url: "https://api.example.com/v1/users?x=1", method: "post", headers: [HTTPHeader(name: "Content-Type", value: "application/json")], at: t0)))
        XCTAssertEqual(start.host, "api.example.com")
        XCTAssertEqual(start.method, "POST")
        XCTAssertTrue(start.isInspected)
        XCTAssertFalse(start.isFinished)

        _ = assembler.apply(.requestPayload(id: 7, data: Data(#"{"a":1}"#.utf8)))
        _ = assembler.apply(.responseStarted(id: 7, status: 201, headers: [HTTPHeader(name: "X-Id", value: "9")]))
        _ = assembler.apply(.responsePayload(id: 7, data: Data("ok".utf8)))
        let done = try XCTUnwrap(assembler.apply(.closed(id: 7, completed: true)))

        XCTAssertEqual(done.status, 201)
        XCTAssertEqual(done.durationMillis, 250)
        XCTAssertEqual(done.sentBytes, 7)
        XCTAssertEqual(done.receivedBytes, 2)
        XCTAssertEqual(done.details?.requestBody, Data(#"{"a":1}"#.utf8))
        XCTAssertEqual(done.details?.responseBody, Data("ok".utf8))
        XCTAssertEqual(done.details?.requestHeaders.first?.name, "Content-Type")
        XCTAssertEqual(done.details?.responseHeaders.first?.value, "9")
    }

    func testEventsOfAnUnknownCallAreIgnored() {
        var assembler = InspectionAssembler()
        XCTAssertNil(assembler.apply(.responseStarted(id: 1, status: 200, headers: [])))
        XCTAssertNil(assembler.apply(.closed(id: 1, completed: true)))
    }

    func testABodyIsCutAtTheCaptureLimitButCounted() throws {
        var assembler = InspectionAssembler()
        _ = assembler.apply(.requestStarted(id: 1, url: "https://h/", method: "GET", headers: [], at: t0))
        let big = Data(repeating: 0x61, count: HTTPMessage.bodyCapture + 500)
        let call = try XCTUnwrap(assembler.apply(.responsePayload(id: 1, data: big)))
        XCTAssertEqual(call.details?.responseBody.count, HTTPMessage.bodyCapture)
        XCTAssertEqual(call.receivedBytes, big.count)
        XCTAssertEqual(call.details?.responseBodyTruncated, true)
    }

    func testOpenCallsAreBounded() {
        var assembler = InspectionAssembler()
        for id in 0..<Int64(InspectionAssembler.maxOpenCalls + 10) {
            _ = assembler.apply(.requestStarted(id: id, url: "https://h/", method: "GET", headers: [], at: t0))
        }
        XCTAssertNil(assembler.apply(.responseStarted(id: 0, status: 200, headers: [])), "the oldest unclosed call was dropped")
        XCTAssertNotNil(assembler.apply(.responseStarted(id: Int64(InspectionAssembler.maxOpenCalls + 9), status: 200, headers: [])))
    }

    func testTheLogUpdatesACallInPlace() {
        var log = APICallLog()
        var call = APICall(id: 3, startedAt: t0, method: "GET", host: "h", url: "https://h/", isTunnel: false)
        call.isInspected = true
        log.upsert(call)
        call.status = 200
        log.upsert(call)
        XCTAssertEqual(log.calls.count, 1)
        XCTAssertEqual(log.calls.first?.status, 200)
        var proxied = APICall(id: 3, startedAt: t0, method: "GET", host: "h", url: "http://h/", isTunnel: false)
        proxied.isInspected = false
        log.upsert(proxied)
        XCTAssertEqual(log.calls.count, 2, "a proxied call with the same number is a different call")
    }
}
