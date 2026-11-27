import XCTest
import TestSupport
@testable import Networking
@testable import Media
@testable import DomainModels
@testable import CoreTestSupport

final class SecurityTests: XCTestCase {
    func testSerialValidationRejectsShellMetacharacters() {
        XCTAssertTrue(AndroidDevice.isValidSerial("R58M12ABCDE"))
        XCTAssertTrue(AndroidDevice.isValidSerial("192.168.1.20:5555"))
        for bad in ["", "a b", "a;rm -rf /", "$(id)", "a`b`", "a\nb", "é"] {
            XCTAssertFalse(AndroidDevice.isValidSerial(bad), bad)
        }
    }

    func testServerArgumentsAreClampedAndClipboardSyncIsOff() {
        var settings = MirrorSettings()
        settings.quality.maxSize = 999_999
        settings.quality.bitRateMbps = -5
        settings.quality.maxFPS = 10_000
        settings.quality.keyFrameIntervalSeconds = 0
        settings.quality.constantBitRate = true
        let arguments = settings.serverArguments(scid: 0xABC)

        XCTAssertTrue(arguments.contains("max_size=4096"))
        XCTAssertTrue(arguments.contains("video_bit_rate=1000000"))
        XCTAssertTrue(arguments.contains("max_fps=120"))
        XCTAssertTrue(arguments.contains("video_codec_options=i-frame-interval:int=1,bitrate-mode:int=2"))

        settings.quality.bitRateMbps = 9_999
        XCTAssertTrue(settings.serverArguments(scid: 1).contains("video_bit_rate=200000000"))
        XCTAssertTrue(arguments.contains("clipboard_autosync=false"))
        XCTAssertTrue(arguments.contains("scid=00000abc"))
        XCTAssertTrue(arguments.allSatisfy { $0.allSatisfy { $0.isASCII && !$0.isWhitespace && !"$;&|`\"'<>()".contains($0) } })
    }

    func testBundledServerMatchesPinnedChecksum() throws {
        let url = projectFile("Resources/\(ServerBundle.fileName)")
        XCTAssertEqual(ServerBundle.digest(of: try Data(contentsOf: url)), ServerBundle.sha256)
    }

    func testListenerIsLoopbackOnlyAndTimesOut() throws {
        let listener = try LoopbackListener()
        XCTAssertGreaterThan(listener.port, 0)
        XCTAssertThrowsError(try listener.accept(timeout: 0.2))
    }

    func testBigEndianRoundTrip() {
        var data = Data()
        data.appendBigEndian(UInt32(0x0102_0304))
        XCTAssertEqual([UInt8](data), [1, 2, 3, 4])
        XCTAssertEqual(data.readBigEndian(UInt32.self, at: 0), 0x0102_0304)
    }

    func testTheServerIsFoundFromADevelopmentBuildWhateverTheWorkingFolder() {
        let package = URL(fileURLWithPath: "/Users/dev/BenzMirror")
        let executable = package.appendingPathComponent(".build/out/Products/Debug/BenzMirror")
        let candidates = ServerBundle.candidateURLs(resources: nil, executable: executable, workingDirectory: URL(fileURLWithPath: "/tmp"))

        XCTAssertTrue(candidates.contains(package.appendingPathComponent("Resources/\(ServerBundle.fileName)")), "Xcode may start the app anywhere")
        XCTAssertEqual(candidates.first, URL(fileURLWithPath: "/tmp/Resources/\(ServerBundle.fileName)"))
        XCTAssertLessThanOrEqual(candidates.count, 10, "the search above the executable is bounded")
    }

    func testTheBundleIsSearchedFirstAndTheSearchStopsAtTheRoot() {
        let bundle = URL(fileURLWithPath: "/Applications/Benz Mirror.app/Contents/Resources")
        let candidates = ServerBundle.candidateURLs(resources: bundle, executable: URL(fileURLWithPath: "/a/b"), workingDirectory: URL(fileURLWithPath: "/w"))
        XCTAssertEqual(candidates.first, bundle.appendingPathComponent(ServerBundle.fileName))
        XCTAssertFalse(candidates.contains { $0.path.hasPrefix("//") })
        XCTAssertTrue(ServerBundle.candidateURLs(resources: nil, executable: nil, workingDirectory: URL(fileURLWithPath: "/w")).count == 1)
    }
}
