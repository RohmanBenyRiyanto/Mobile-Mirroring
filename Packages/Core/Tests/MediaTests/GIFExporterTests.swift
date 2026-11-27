import AVFoundation
import ImageIO
import XCTest
@testable import Media

final class GIFExporterTests: XCTestCase {
    func testFrameTimesFollowTheRangeAndAreClamped() {
        let times = GIFExporter.frameTimes(duration: 5, options: .init(start: 1, length: 2, framesPerSecond: 10))
        XCTAssertEqual(times.count, 20)
        XCTAssertEqual(times.first, 1)
        XCTAssertTrue(GIFExporter.frameTimes(duration: 1, options: .init(start: 5, length: 2)).isEmpty)
        XCTAssertEqual(GIFExporter.Options(start: -3, length: 999, framesPerSecond: 500, maxWidth: 99999).clamped, .init(start: 0, length: 30, framesPerSecond: 24, maxWidth: 960))
    }

    private func makeVideo(at url: URL, seconds: Int) throws {
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 192])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 192])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 10) {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 128, 192, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 7 % 255), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 10))
        }
        input.markAsFinished()
        let done = expectation(description: "written")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
    }

    func testExportsAnAnimatedGIF() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gif-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("in.mp4"), gif = folder.appendingPathComponent("out.gif")
        try makeVideo(at: video, seconds: 2)
        try await GIFExporter.export(video: video, to: gif, options: .init(start: 0, length: 1, framesPerSecond: 5, maxWidth: 64))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 5)
        let first = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(first.width, 64)
    }

    func testAFileWithoutVideoIsRefused() async throws {
        let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data("not a video".utf8).write(to: text)
        defer { try? FileManager.default.removeItem(at: text) }
        do {
            try await GIFExporter.export(video: text, to: text.appendingPathExtension("gif"))
            XCTFail("should have thrown")
        } catch {}
    }
}
