import AVFoundation
import XCTest
@testable import Media
@testable import DomainModels
@testable import CoreTestSupport

/// Feeds a real H.264 clip through the same path the device stream takes:
/// Annex-B packets → `VideoDecoder` → display layer, and → `ScreenRecorder` → MP4.
final class RecordingPipelineTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    func testStreamIsDecodedAndRecordedToPlayableMP4() async throws {
        let units = try makeH264Clip(seconds: 2, fps: 30)
        let parameterSets = units.filter { [7, 8].contains($0[0] & 0x1F) }
        let slices = units.filter { [1, 5].contains($0[0] & 0x1F) }
        XCTAssertEqual(slices.count, 60)

        let decoder = VideoDecoder(codec: .h264)
        try decoder.configure(with: parameterSets.reduce(into: Data()) { $0.append(Self.startCode + $1) })
        let format = try XCTUnwrap(decoder.currentFormat)

        let outputURL = workDirectory.appendingPathComponent("out.mp4")
        let recorder = try ScreenRecorder(url: outputURL, videoFormat: format, includesAudio: true)
        decoder.setFrameTap { sample, isKeyFrame in recorder.appendVideo(sample, isKeyFrame: isKeyFrame) }

        for (index, slice) in slices.enumerated() {
            let presentationTime = Int64(index) * 33_333
            decoder.decode(Self.startCode + slice, presentationTime: presentationTime, isKeyFrame: slice[0] & 0x1F == 5)
            if index % 3 == 0 { // 16 ms of silence per packet
                recorder.appendAudio(Data(count: 768 * SampleBuffers.PCM.bytesPerFrame), presentationTime: presentationTime)
            }
        }
        XCTAssertFalse(decoder.hasDisplayError)

        let url = try await recorder.finish()

        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(video.count, 1)
        let size = try await video[0].load(.naturalSize)
        XCTAssertEqual(size.width, 320)
        XCTAssertEqual(size.height, 240)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.3)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1)
    }

    func testFramesBeforeFirstKeyFrameAreIgnored() async throws {
        let units = try makeH264Clip(seconds: 1, fps: 30)
        let parameterSets = units.filter { [7, 8].contains($0[0] & 0x1F) }
        let slices = units.filter { [1, 5].contains($0[0] & 0x1F) }

        let decoder = VideoDecoder(codec: .h264)
        try decoder.configure(with: parameterSets.reduce(into: Data()) { $0.append(Self.startCode + $1) })
        let recorder = try ScreenRecorder(url: workDirectory.appendingPathComponent("late.mp4"),
                                          videoFormat: try XCTUnwrap(decoder.currentFormat), includesAudio: false)
        decoder.setFrameTap { sample, isKeyFrame in recorder.appendVideo(sample, isKeyFrame: isKeyFrame) }

        // Only delta frames: nothing may be written, and finishing must clean up.
        for (index, slice) in slices.enumerated() where slice[0] & 0x1F == 1 {
            decoder.decode(Self.startCode + slice, presentationTime: Int64(index) * 33_333, isKeyFrame: false)
        }
        do {
            _ = try await recorder.finish()
            XCTFail("expected nothingRecorded")
        } catch RecordingError.nothingRecorded {
            XCTAssertFalse(FileManager.default.fileExists(atPath: workDirectory.appendingPathComponent("late.mp4").path))
        }
    }

    // MARK: Helpers

    private static let startCode = Data([0, 0, 0, 1])

    /// Encodes a test pattern with ffmpeg (no B-frames, like the Android encoder) and returns its NAL units.
    private func makeH264Clip(seconds: Int, fps: Int) throws -> [Data] {
        let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let ffmpeg else { throw XCTSkip("ffmpeg is not installed") }

        let clip = workDirectory.appendingPathComponent("clip.h264")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=\(fps)", "-t", "\(seconds)",
                             "-c:v", "libx264", "-bf", "0", "-g", "15", "-pix_fmt", "yuv420p", "-f", "h264", clip.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw XCTSkip("ffmpeg could not encode the test clip") }

        return AnnexB.nalUnits(in: try Data(contentsOf: clip))
    }
}
