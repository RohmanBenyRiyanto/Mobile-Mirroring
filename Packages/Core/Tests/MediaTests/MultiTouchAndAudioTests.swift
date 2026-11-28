import AVFoundation
import XCTest
@testable import Media
@testable import DomainModels
@testable import CoreTestSupport

final class MultiTouchAndAudioTests: XCTestCase {
    private let center = TouchPosition(x: 540, y: 1200, frameWidth: 1080, frameHeight: 2400)

    func testPointerIDsAreDistinctOnTheWire() {
        func pointer(_ id: PointerID) -> UInt64 {
            ControlMessage.touch(.down, center, pressure: 1, pointer: id).serialized.readBigEndian(UInt64.self, at: 2)
        }
        XCTAssertEqual(pointer(.mouse), UInt64.max)
        XCTAssertEqual(pointer(.finger), UInt64.max - 1)
        XCTAssertEqual(pointer(.virtualFinger), UInt64.max - 2)
    }

    func testPinchFingersStartSymmetricAroundCenter() {
        let fingers = PinchGesture(center: center).fingers
        XCTAssertEqual(fingers.first.y, 1200)
        XCTAssertEqual(fingers.second.y, 1200)
        XCTAssertEqual(540 - fingers.first.x, fingers.second.x - 540)
    }

    func testPinchScaleMovesFingersAndIsBounded() {
        var gesture = PinchGesture(center: center)
        let initial = gesture.spread
        gesture.scale(by: 2)
        XCTAssertEqual(gesture.spread, initial * 2, accuracy: 0.001)

        gesture.scale(by: 1_000)
        XCTAssertLessThanOrEqual(gesture.spread, 540)
        gesture.scale(by: 0.000_001)
        XCTAssertGreaterThanOrEqual(gesture.spread, 12)
    }

    func testPinchNearEdgeStaysInsideFrame() {
        let edge = TouchPosition(x: 2, y: 5, frameWidth: 1080, frameHeight: 2400)
        let fingers = PinchGesture(center: edge).fingers
        XCTAssertGreaterThanOrEqual(fingers.first.x, 0)
        XCTAssertLessThan(fingers.second.x, 1080)
    }

    func testMirroredFingerIsOppositeThroughCenter() {
        let mirrored = PinchGesture.mirrored(TouchPosition(x: 100, y: 300, frameWidth: 1080, frameHeight: 2400))
        XCTAssertEqual(mirrored.x, 979)
        XCTAssertEqual(mirrored.y, 2099)
    }

    func testPCMConversionToPlanarFloat() throws {
        var pcm = Data()
        for sample: Int16 in [Int16.max, Int16.min, 0, 16_384] {
            pcm.append(contentsOf: Swift.withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8))

        AudioPlayer.fill(buffer, fromInterleavedInt16: pcm)

        XCTAssertEqual(buffer.frameLength, 2)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertEqual(channels[0][0], Float(Int16.max) / 32768, accuracy: 1e-6)
        XCTAssertEqual(channels[1][0], -1, accuracy: 1e-6)
        XCTAssertEqual(channels[0][1], 0, accuracy: 1e-6)
        XCTAssertEqual(channels[1][1], 0.5, accuracy: 1e-6)
    }

    func testAudioSampleBufferCarriesWholeFrames() throws {
        let pcm = Data(count: 4_800 * SampleBuffers.PCM.bytesPerFrame + 3)
        let sample = try XCTUnwrap(SampleBuffers.audio(pcm, presentationTime: 1_000_000))
        XCTAssertEqual(CMSampleBufferGetNumSamples(sample), 4_800)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample).seconds, 1, accuracy: 1e-9)
        XCTAssertNil(SampleBuffers.audio(Data(count: 3), presentationTime: 0))
    }

    func testAudioIsRequestedAsRawPCM() {
        var settings = MirrorSettings()
        XCTAssertTrue(settings.serverArguments(scid: 1).contains("audio=true"))
        XCTAssertTrue(settings.serverArguments(scid: 1).contains("audio_codec=raw"))
        settings.audioEnabled = false
        XCTAssertTrue(settings.serverArguments(scid: 1).contains("audio=false"))
    }
}

final class AudioBacklogTests: XCTestCase {
    func testALongBacklogIsDroppedOnceAndPlaybackContinues() throws {
        let player = AudioPlayer()
        do { try player.start() } catch { throw XCTSkip("no audio output on this machine: \(error)") }
        defer { player.stop() }
        player.isMuted = true
        let chunk = Data(count: 4_800 * SampleBuffers.PCM.bytesPerFrame)
        for _ in 0..<3 { player.enqueue(chunk) }
        XCTAssertEqual(player.droppedBacklogs, 1, "300 ms queued: dropped once, then playing from the newest audio")
    }
}

final class AudioOutputDeviceTests: XCTestCase {
    func testListsOutputsAndResolvesTheirUIDs() throws {
        let devices = AudioOutputDevices.all()
        guard let first = devices.first else { throw XCTSkip("no audio output on this machine") }
        XCTAssertFalse(first.name.isEmpty)
        XCTAssertNotNil(AudioOutputDevices.deviceID(forUID: first.uid))
        XCTAssertNil(AudioOutputDevices.deviceID(forUID: "no-such-device"))
    }
}
