import XCTest
import TestSupport
@testable import Networking
@testable import Media
@testable import DomainModels
@testable import CoreTestSupport

final class TransportStreamTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    // MARK: Muxer

    func testCRC32MatchesTheMPEG2CheckValue() {
        XCTAssertEqual(TransportStreamMuxer.crc32(Data("123456789".utf8)), 0x0376_E6E7)
    }

    func testTablesAreTwoValidPackets() {
        var muxer = TransportStreamMuxer(codec: .h264, includesAudio: true)
        let tables = muxer.tables()
        XCTAssertEqual(tables.count, 376)
        XCTAssertEqual(tables[0], 0x47)
        XCTAssertEqual(tables[188], 0x47)
        // A PSI section ending with its CRC must itself have a CRC of zero.
        XCTAssertEqual(TransportStreamMuxer.crc32(tables[5..<21]), 0) // the 16-byte PAT section, CRC included
    }

    /// Every size around the 184-byte payload boundary must pack into whole packets and read back unchanged.
    func testPacketizationRoundTripsForEveryPayloadSize() throws {
        for size in 1...700 {
            var muxer = TransportStreamMuxer(codec: .h264, includesAudio: true)
            let payload = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })

            for (isKeyFrame, pid, ticks) in [(true, TransportStreamMuxer.videoPID, UInt64(123_456)), (false, TransportStreamMuxer.videoPID, 90_000)] {
                let packets = muxer.video(payload, ticks: ticks, isKeyFrame: isKeyFrame)
                XCTAssertEqual(packets.count % 188, 0, "size \(size)")
                let expected = TransportStreamMuxer.pes(streamID: 0xE0, payload: payload, ticks: ticks, boundedLength: false)
                XCTAssertEqual(try extractPayload(from: packets, pid: pid), expected, "size \(size)")
            }

            let audio = muxer.audio(payload, ticks: 5_000)
            let expectedAudio = TransportStreamMuxer.pes(streamID: 0xC0, payload: payload, ticks: 5_000, boundedLength: true)
            XCTAssertEqual(try extractPayload(from: audio, pid: TransportStreamMuxer.audioPID), expectedAudio, "audio size \(size)")
        }
    }

    func testContinuityCountersIncrementAndWrap() throws {
        var muxer = TransportStreamMuxer(codec: .h264, includesAudio: false)
        var counters: [UInt8] = []
        for _ in 0..<20 {
            let packets = muxer.video(Data(count: 10), ticks: 90_000, isKeyFrame: false)
            counters.append(packets[3] & 0x0F)
        }
        XCTAssertEqual(counters, (0..<20).map { UInt8($0 % 16) })
    }

    func testKeyFramePacketCarriesPCRAndRandomAccessFlag() {
        var muxer = TransportStreamMuxer(codec: .h264, includesAudio: false)
        let packet = muxer.video(Data(count: 1_000), ticks: 180_000, isKeyFrame: true)
        XCTAssertEqual(packet[1] & 0x40, 0x40) // payload unit start
        XCTAssertEqual(packet[3] & 0x30, 0x30) // adaptation field and payload
        XCTAssertEqual(packet[5] & 0x50, 0x50) // random access + PCR flags
    }

    func testAACFramesGetValidADTSHeaders() throws {
        let encoder = try XCTUnwrap(AACEncoder())
        var frames: [AACEncoder.Frame] = []
        for index in 0..<10 {
            frames += encoder.encode(Data(count: 1_024 * 4), presentationTime: Int64(index) * 21_333)
        }
        XCTAssertGreaterThanOrEqual(frames.count, 8) // the encoder holds back one block of priming
        for frame in frames {
            XCTAssertEqual(frame.adts[0], 0xFF)
            XCTAssertEqual(frame.adts[1] & 0xF0, 0xF0)
            let length = (Int(frame.adts[3] & 0x03) << 11) | (Int(frame.adts[4]) << 3) | Int(frame.adts[5] >> 5)
            XCTAssertEqual(length, frame.adts.count)
        }
        XCTAssertEqual(frames[1].presentationTime - frames[0].presentationTime, 21_333, accuracy: 1)
    }

    // MARK: Full path: server over HTTP, decoded by ffmpeg

    func testViewerReceivesAStreamThatFFmpegDecodesCleanly() async throws {
        let units = try makeH264NALUnits(in: workDirectory, seconds: 2, fps: 30)
        let config = units.filter { [7, 8].contains($0[0] & 0x1F) }.reduce(into: Data()) { $0.append(annexBStartCode + $1) }
        let slices = units.filter { [1, 5].contains($0[0] & 0x1F) }

        let server = try TransportStreamServer(codec: .h264, port: 0, includesAudio: true)
        server.start()
        defer { server.stop() }
        let viewerConnected = expectation(description: "viewer connected")
        server.onViewerConnected = { viewerConnected.fulfill() }

        let viewer = try connectLoopback(port: server.port)
        viewer.setTimeouts(seconds: 5)
        try viewer.write(Data("GET /live.ts HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))
        await fulfillment(of: [viewerConnected], timeout: 3)

        server.submitConfig(config)
        for (index, slice) in slices.enumerated() {
            let time = Int64(index) * 33_333
            server.submitVideo(annexBStartCode + slice, presentationTime: time, isKeyFrame: slice[0] & 0x1F == 5)
            server.submitAudio(Data(count: 1_600 * 4), presentationTime: time) // 33 ms of silence per frame
        }
        try await Task.sleep(for: .milliseconds(600)) // let the queues drain
        server.stop()

        var response = Data()
        while let chunk = try? viewer.readSome(limit: 65_536), !chunk.isEmpty { response.append(chunk) }

        let separator = Data("\r\n\r\n".utf8)
        let headerEnd = try XCTUnwrap(response.range(of: separator))
        let head = String(decoding: response[..<headerEnd.lowerBound], as: UTF8.self)
        XCTAssertTrue(head.hasPrefix("HTTP/1.1 200 OK"))
        XCTAssertTrue(head.contains("Content-Type: video/mp2t"))

        let body = Data(response[headerEnd.upperBound...])
        XCTAssertEqual(body.count % 188, 0)
        XCTAssertEqual(body[body.startIndex], 0x47)
        XCTAssertEqual(Int(body[body.startIndex + 1] & 0x1F) << 8 | Int(body[body.startIndex + 2]), 0, "the stream must open with the PAT")

        let file = workDirectory.appendingPathComponent("received.ts")
        try body.write(to: file)

        let decode = try runTool("ffmpeg", ["-v", "error", "-i", file.path, "-f", "null", "-"])
        XCTAssertEqual(decode.status, 0)
        XCTAssertEqual(decode.errors, "", "ffmpeg reported problems decoding the stream")

        let probe = try runTool("ffprobe", ["-v", "error", "-show_streams", "-of", "json", file.path])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(probe.output.utf8)) as? [String: Any])
        let streams = try XCTUnwrap(json["streams"] as? [[String: Any]])
        XCTAssertEqual(streams.compactMap { $0["codec_name"] as? String }, ["h264", "aac"])
        XCTAssertEqual(streams[0]["width"] as? Int, 320)
        XCTAssertEqual(streams[0]["height"] as? Int, 240)
        XCTAssertEqual(streams[1]["sample_rate"] as? String, "48000")
        XCTAssertEqual(streams[1]["channels"] as? Int, 2)
    }

    func testViewerOnlyStartsAtAKeyFrame() async throws {
        let server = try TransportStreamServer(codec: .h264, port: 0, includesAudio: false)
        server.start()
        defer { server.stop() }

        let viewer = try connectLoopback(port: server.port)
        viewer.setTimeouts(seconds: 2)
        try viewer.write(Data("GET / HTTP/1.1\r\n\r\n".utf8))
        while server.viewerCount == 0 { try await Task.sleep(for: .milliseconds(20)) }

        server.submitVideo(annexBStartCode + Data([0x41, 1, 2, 3]), presentationTime: 0, isKeyFrame: false)
        server.submitVideo(annexBStartCode + Data([0x65, 1, 2, 3]), presentationTime: 33_333, isKeyFrame: true)
        try await Task.sleep(for: .milliseconds(300))

        var response = Data()
        while response.range(of: Data([0x47, 0x40, 0x00])) == nil, let chunk = try? viewer.readSome(limit: 65_536), !chunk.isEmpty {
            response.append(chunk)
        }
        let headerEnd = try XCTUnwrap(response.range(of: Data("\r\n\r\n".utf8)))
        let body = Data(response[headerEnd.upperBound...])
        XCTAssertEqual(body.first, 0x47)
        XCTAssertEqual(body.count % 188, 0)
        // PAT, PMT, then the key frame: three packets minimum, and nothing before the PAT.
        XCTAssertGreaterThanOrEqual(body.count, 188 * 3)
        XCTAssertEqual(Int(body[1] & 0x1F) << 8 | Int(body[2]), 0)
    }

    func testRequestsThatAreNotGETAreRejected() throws {
        let server = try TransportStreamServer(codec: .h264, port: 0, includesAudio: false)
        server.start()
        defer { server.stop() }

        let client = try connectLoopback(port: server.port)
        client.setTimeouts(seconds: 2)
        try client.write(Data("POST / HTTP/1.1\r\n\r\n".utf8))
        XCTAssertEqual(try client.readSome(limit: 100).count, 0)
        XCTAssertEqual(server.viewerCount, 0)
    }

    func testPortInUseGivesAClearError() throws {
        let first = try LoopbackListener()
        XCTAssertThrowsError(try LoopbackListener(port: first.port)) { error in
            guard case SocketError.addressInUse = error else { return XCTFail("unexpected \(error)") }
        }
    }

    // MARK: Helpers

    /// Concatenates the payload bytes of every packet on `pid`, validating framing along the way.
    private func extractPayload(from stream: Data, pid: UInt16) throws -> Data {
        var payload = Data()
        for start in stride(from: 0, to: stream.count, by: 188) {
            let packet = stream[stream.startIndex + start..<stream.startIndex + start + 188]
            let base = packet.startIndex
            XCTAssertEqual(packet[base], 0x47)
            guard UInt16(packet[base + 1] & 0x1F) << 8 | UInt16(packet[base + 2]) == pid else { continue }

            let control = (packet[base + 3] >> 4) & 0x03
            var offset = 4
            if control & 0x02 != 0 { offset += 1 + Int(packet[base + 4]) }
            XCTAssertLessThanOrEqual(offset, 188)
            if control & 0x01 != 0 { payload.append(packet[(base + offset)...]) }
        }
        return payload
    }
}
