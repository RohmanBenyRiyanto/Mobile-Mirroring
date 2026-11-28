import XCTest
@testable import DomainModels
@testable import Networking
@testable import WorkspaceFeature

final class QualityTests: XCTestCase {
    func testEveryPresetRoundTripsThroughMatching() {
        for preset in QualityPreset.allCases where preset != .custom {
            let values = try? XCTUnwrap(VideoQuality.values(for: preset))
            XCTAssertEqual(values?.matchingPreset, preset)
        }
    }

    func testEditingAPresetMakesItCustom() {
        var quality = VideoQuality.values(for: .gaming)!
        quality.bitRateMbps += 1
        XCTAssertEqual(quality.matchingPreset, .custom)
    }

    func testGamingPresetIsTunedForStreaming() {
        let gaming = VideoQuality.values(for: .gaming)!
        XCTAssertEqual(gaming.maxSize, 0, "native resolution")
        XCTAssertTrue(gaming.constantBitRate)
        XCTAssertEqual(gaming.keyFrameIntervalSeconds, 1, "short key frame interval so OBS can join quickly")
    }

    func testPresetsStayInsideTheAllowedRanges() {
        for preset in QualityPreset.allCases {
            guard let quality = VideoQuality.values(for: preset) else { continue }
            XCTAssertTrue(VideoQuality.maxSizeRange.contains(quality.maxSize))
            XCTAssertTrue(VideoQuality.bitRateRange.contains(quality.bitRateMbps))
            XCTAssertTrue(VideoQuality.frameRateRange.contains(quality.maxFPS))
            XCTAssertTrue(VideoQuality.keyFrameIntervalRange.contains(quality.keyFrameIntervalSeconds))
        }
    }

    func testSettingsSurviveARoundTripThroughUserDefaults() throws {
        let suite = "benzmirror.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(SettingsStore.load(from: defaults), MirrorSettings(), "defaults when nothing is stored")

        var settings = MirrorSettings()
        settings.quality = VideoQuality.values(for: .maximum)!
        settings.obsStreamEnabled = true
        settings.obsStreamPort = 9000
        SettingsStore.save(settings, to: defaults)
        XCTAssertEqual(SettingsStore.load(from: defaults), settings)

        defaults.set(Data("not json".utf8), forKey: "mirrorSettings.v1")
        XCTAssertEqual(SettingsStore.load(from: defaults), MirrorSettings(), "corrupt data falls back to defaults")
    }
}

final class WirelessTests: XCTestCase {
    func testAddressValidation() {
        for good in ["192.168.1.20:5555", "pixel.local:37099", "a-b.c:1", "10.0.0.1:65535"] {
            XCTAssertTrue(WirelessInput.isValidAddress(good), good)
        }
        for bad in ["", "192.168.1.20", ":5555", "host:0", "host:65536", "host:abc", "a:b:c", "ho st:5555", "host;ls:5555", "$(id):1", "-s:5555x"] {
            XCTAssertFalse(WirelessInput.isValidAddress(bad), bad)
        }
    }

    func testPairingCodeValidation() {
        XCTAssertTrue(WirelessInput.isValidPairingCode("123456"))
        for bad in ["", "12345", "1234567", "12345a", "12 456", "١٢٣٤٥٦"] {
            XCTAssertFalse(WirelessInput.isValidPairingCode(bad), bad)
        }
    }

    private let phoneOutput = """
    1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever preferred_lft forever
    30: rmnet_data0    inet 10.145.185.197/30 brd 10.145.185.199 scope global rmnet_data0\\       valid_lft forever preferred_lft forever
    56: swlan0    inet 10.188.58.133/24 brd 10.188.58.255 scope global swlan0\\       valid_lft forever preferred_lft forever
    """

    func testPhoneInterfacesAreParsedAndLoopbackIsSkipped() {
        let interfaces = WirelessInput.interfaces(inIPOutput: phoneOutput)
        XCTAssertEqual(interfaces.map(\.name), ["rmnet_data0", "swlan0"])
        XCTAssertEqual(interfaces.last?.text, "10.188.58.133")
        XCTAssertEqual(interfaces.last?.prefix, 24)
        XCTAssertTrue(WirelessInput.interfaces(inIPOutput: "Device \"wlan0\" does not exist.").isEmpty)
    }

    func testTheAddressOnTheMacsNetworkIsChosenOverMobileData() throws {
        let phone = WirelessInput.interfaces(inIPOutput: phoneOutput)
        let hotspotMac = IPv4Interface(name: "en0", address: try XCTUnwrap(IPv4Interface.parse("10.188.58.198")), prefix: 24)
        XCTAssertEqual(WirelessInput.reachableAddress(phone: phone, mac: [hotspotMac])?.name, "swlan0")

        let otherNetwork = IPv4Interface(name: "en0", address: try XCTUnwrap(IPv4Interface.parse("192.168.1.5")), prefix: 24)
        XCTAssertNil(WirelessInput.reachableAddress(phone: phone, mac: [otherNetwork]), "different networks cannot work")
    }

    func testIPv4ParsingRejectsMalformedText() {
        XCTAssertEqual(IPv4Interface.parse("10.0.0.1"), 0x0A00_0001)
        for bad in ["", "10.0.0", "10.0.0.256", "10.0.0.1.1", "a.b.c.d", "10..0.1"] {
            XCTAssertNil(IPv4Interface.parse(bad), bad)
        }
        XCTAssertEqual(IPv4Interface.format(0xC0A8_0114), "192.168.1.20")
    }

    func testThisMacHasANonLoopbackInterface() {
        XCTAssertFalse(IPv4Interface.ofThisMac().contains { $0.name == "lo0" })
    }
}

final class AppIdentityTests: XCTestCase {
    func testTheProductIsCalledBenzMirror() throws {
        XCTAssertEqual(AppInfo.name, "Benz Mirror")
        let url = try OutputFiles.newURL(in: .moviesDirectory, prefix: "Recording", pathExtension: "mp4")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Benz Mirror")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Recording-"))
    }
}

final class DeviceToolTests: XCTestCase {
    func testCommandsAreFixedAndShellSafe() {
        for tool in DeviceTool.allCases {
            XCTAssertFalse(tool.shellCommands.isEmpty)
            for argument in tool.shellCommands.joined() {
                XCTAssertTrue(argument.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }, argument)
            }
        }
        XCTAssertEqual(DeviceTool.animationsOff.shellCommands.count, 3)
    }

    func testFileNamesSentToThePhoneAreSanitized() {
        XCTAssertEqual(OutputFiles.sanitizedName("holiday photo (1).jpg"), "holiday photo (1).jpg")
        XCTAssertEqual(OutputFiles.sanitizedName("a/b;rm -rf `x`.txt"), "a_b_rm -rf _x_.txt")
        XCTAssertEqual(OutputFiles.sanitizedName("../../etc/passwd"), "file.._.._etc_passwd")
        XCTAssertTrue(OutputFiles.sanitizedName(".hidden").hasPrefix("file"))
        XCTAssertEqual(OutputFiles.sanitizedName(String(repeating: "a", count: 500)).count, 120)
        XCTAssertEqual(OutputFiles.sanitizedName(""), "file")
    }
}

final class LogcatTests: XCTestCase {
    func testThreadtimeLinesAreParsed() {
        let line = "11-27 14:20:41.881  1234  1250 W ActivityManager: Slow operation"
        XCTAssertEqual(LogEntry.parse(line, id: 1).level, .warning)
        XCTAssertEqual(LogEntry.parse("11-27 14:20:41.881  1 2 E Tag: boom", id: 2).level, .error)
        XCTAssertEqual(LogEntry.parse("--------- beginning of main", id: 3).level, .verbose)
        XCTAssertEqual(LogEntry.parse("", id: 4).level, .verbose)
    }

    func testLevelsOrderBySeverity() {
        XCTAssertLessThan(LogLevel.debug, .error)
        XCTAssertEqual(LogLevel(letter: "F"), .fatal)
        XCTAssertNil(LogLevel(letter: "X"))
    }

    func testLineBufferJoinsLinesSplitAcrossChunks() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("first\nsec".utf8)), ["first"])
        XCTAssertEqual(buffer.append(Data("ond\nthi".utf8)), ["second"])
        XCTAssertEqual(buffer.append(Data("rd\r\n".utf8)), ["third"])
        XCTAssertEqual(buffer.append(Data()), [])
    }
}

final class StatisticsTests: XCTestCase {
    func testRatesCoverTheWindowAndThenReset() {
        let statistics = StreamStatistics()
        let start = Date()
        for _ in 0..<60 { statistics.recordVideoPacket(bytes: 25_000, isFrame: true) }
        statistics.recordVideoPacket(bytes: 40, isFrame: false)

        let first = statistics.snapshot(now: start.addingTimeInterval(2))
        XCTAssertEqual(first.framesPerSecond, 30, accuracy: 3)
        XCTAssertEqual(first.megabitsPerSecond, 6, accuracy: 0.6)

        let second = statistics.snapshot(now: start.addingTimeInterval(3))
        XCTAssertEqual(second, StreamStatistics.Snapshot())
    }
}
