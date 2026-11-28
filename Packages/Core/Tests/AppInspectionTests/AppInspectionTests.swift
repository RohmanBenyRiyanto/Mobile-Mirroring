import DomainModels
import XCTest
@testable import AppInspection

final class InspectorFilesTests: XCTestCase {
    func testThePhonesProcessorDecidesTheBuild() {
        XCTAssertEqual(PhoneABI(abi: "arm64-v8a\n")?.agentSuffix, "arm64")
        XCTAssertEqual(PhoneABI(abi: "armeabi-v7a")?.agentSuffix, "arm")
        XCTAssertEqual(PhoneABI(abi: "x86_64")?.folder, "x86_64")
        XCTAssertNil(PhoneABI(abi: "mips"))
    }

    func testStudioIsFoundOnlyWhenEveryFileIsThere() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "/Android Studio.app", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let abi = try XCTUnwrap(PhoneABI(abi: "arm64-v8a"))
        XCTAssertNil(InspectorFiles.locate(abi: abi, roots: [root]))

        let resources = root.appendingPathComponent("Contents/plugins/android/resources")
        for path in ["transport/arm64-v8a/transport", "transport/native/agent/arm64-v8a/libjvmtiagent.so", "perfa.jar"] {
            let url = resources.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
        }
        XCTAssertNil(InspectorFiles.locate(abi: abi, roots: [root]), "the network inspector is still missing")
        let inspector = resources.appendingPathComponent("app-inspection/network-inspector.jar")
        try FileManager.default.createDirectory(at: inspector.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: inspector)
        XCTAssertEqual(InspectorFiles.locate(abi: abi, roots: [root])?.perfa.lastPathComponent, "perfa.jar")
    }

    func testTheConfigFilesMatchWhatAndroidStudioWrites() {
        XCTAssertEqual(InspectorConfig.daemon.count, 59)
        XCTAssertEqual(InspectorConfig.agent.count, 63)
        XCTAssertTrue(String(decoding: InspectorConfig.daemon, as: UTF8.self).contains("AndroidStudioTransport"))
    }
}

final class NetworkEventMapperTests: XCTestCase {
    func testARequestStartIsMapped() throws {
        var started = Studio_Network_Inspection_HttpConnectionEvent.RequestStarted()
        started.url = "https://api.example.com/x"
        started.method = "GET"
        var header = Studio_Network_Inspection_HttpConnectionEvent.Header()
        header.key = "Accept"; header.values = ["application/json"]
        started.headers = [header]
        var http = Studio_Network_Inspection_HttpConnectionEvent()
        http.connectionID = 5
        http.httpRequestStarted = started
        var event = Studio_Network_Inspection_Event()
        event.httpConnectionEvent = http
        let mapped = try XCTUnwrap(NetworkEventMapper.map(event, at: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(mapped, .requestStarted(id: 5, url: "https://api.example.com/x", method: "GET", headers: [HTTPHeader(name: "Accept", value: "application/json")], at: Date(timeIntervalSince1970: 1)))
    }

    func testSpeedEventsAreNotCalls() {
        var event = Studio_Network_Inspection_Event()
        event.speedEvent = Studio_Network_Inspection_SpeedEvent()
        XCTAssertNil(NetworkEventMapper.map(event))
    }

    func testABodyKeepsItsBytes() throws {
        var payload = Studio_Network_Inspection_HttpConnectionEvent.Payload()
        payload.payload = Data("hello".utf8)
        var http = Studio_Network_Inspection_HttpConnectionEvent()
        http.connectionID = 2
        http.responsePayload = payload
        var event = Studio_Network_Inspection_Event()
        event.httpConnectionEvent = http
        XCTAssertEqual(NetworkEventMapper.map(event), .responsePayload(id: 2, data: Data("hello".utf8)))
    }
}
