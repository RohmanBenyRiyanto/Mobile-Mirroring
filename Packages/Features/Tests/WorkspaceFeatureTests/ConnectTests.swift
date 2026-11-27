import DomainModels
import Networking
import SwiftUI
import TestSupport
import Theme
import XCTest
@testable import WorkspaceFeature

final class ConnectStatusTests: XCTestCase {
    private func device(_ serial: String = "ABC123", _ state: AndroidDevice.State = .device) -> AndroidDevice {
        AndroidDevice(serial: serial, state: state, model: "Pixel_8")
    }

    private func status(adbMissing: Bool = false, devices: [AndroidDevice], selected: AndroidDevice?, state: AppModel.State = .idle) -> ConnectStatus {
        ConnectStatus.make(adbMissing: adbMissing, devices: devices, selected: selected, state: state)
    }

    func testMissingAdbBlocksEverything() {
        let s = status(adbMissing: true, devices: [device()], selected: device())
        XCTAssertEqual(s.banner, .adbMissing)
        XCTAssertFalse(s.canStart)
    }

    func testNoPhoneAsksToConnectOne() {
        let s = status(devices: [], selected: nil)
        XCTAssertEqual(s.banner, .noDevice)
        XCTAssertFalse(s.canStart)
    }

    func testReadyPhoneCanStartWithoutABanner() {
        let s = status(devices: [device()], selected: device())
        XCTAssertNil(s.banner)
        XCTAssertTrue(s.canStart)
        XCTAssertFalse(s.isStarting)
    }

    func testUnauthorizedAndOfflinePhonesCannotStart() {
        XCTAssertEqual(status(devices: [device("A", .unauthorized)], selected: device("A", .unauthorized)).banner, .unauthorized)
        XCTAssertEqual(status(devices: [device("A", .offline)], selected: device("A", .offline)).banner, .offline)
        XCTAssertEqual(status(devices: [device("A", .other)], selected: device("A", .other)).banner, .offline)
        XCTAssertFalse(status(devices: [device("A", .unauthorized)], selected: device("A", .unauthorized)).canStart)
    }

    func testFailedStartKeepsThePhoneReadyToTryAgain() {
        let s = status(devices: [device()], selected: device(), state: .failed("boom"))
        XCTAssertEqual(s.banner, .failed("boom"))
        XCTAssertTrue(s.canStart)
    }

    func testStartingShowsProgressAndBlocksASecondStart() {
        let s = status(devices: [device()], selected: device(), state: .connecting)
        XCTAssertTrue(s.isStarting)
        XCTAssertFalse(s.canStart)
        XCTAssertNil(s.banner)
    }

    func testPhonesExistButNoneSelectedShowsNoBanner() {
        let s = status(devices: [device()], selected: nil)
        XCTAssertNil(s.banner)
        XCTAssertFalse(s.canStart)
    }
}

final class ConnectTextTests: XCTestCase {
    func testTransportComesFromTheSerial() {
        XCTAssertEqual(ConnectText.transport(of: AndroidDevice(serial: "3A1F9C27", state: .device, model: nil)), "USB")
        XCTAssertEqual(ConnectText.transport(of: AndroidDevice(serial: "192.168.1.24:41233", state: .device, model: nil)), "Wi-Fi")
    }

    func testDeviceLines() {
        let usb = AndroidDevice(serial: "3A1F9C27", state: .unauthorized, model: "Pixel_8")
        XCTAssertEqual(ConnectText.deviceStatus(usb), "USB · Unauthorized")
        XCTAssertEqual(ConnectText.deviceDetail(usb), "USB · 3A1F9C27")
    }

    func testQualityCardsShowTheRealValues() throws {
        let balanced = try XCTUnwrap(VideoQuality.values(for: .balanced))
        XCTAssertEqual(ConnectText.qualitySummary(balanced), "1920 px · 60 fps · 8 Mbps")
        let gaming = try XCTUnwrap(VideoQuality.values(for: .gaming))
        XCTAssertEqual(ConnectText.qualitySummary(gaming), "Native · 60 fps · steady 40 Mbps")
        let maximum = try XCTUnwrap(VideoQuality.values(for: .maximum))
        XCTAssertEqual(ConnectText.qualitySummary(maximum), "Native · 120 fps · steady 80 Mbps")
        XCTAssertEqual(ConnectText.advancedSummary(maximum), "H.265 · Native · 120 fps")
    }

    func testPickerKeepsASavedValueThatIsNotAUsualChoice() {
        XCTAssertEqual(ConnectText.options([30, 60, 90, 120], including: 60), [30, 60, 90, 120])
        XCTAssertEqual(ConnectText.options([30, 60, 90, 120], including: 75), [30, 60, 75, 90, 120])
        XCTAssertEqual(ConnectText.options([0, 1280], including: 4000), [0, 1280, 4000])
    }
}

/// Both languages must be complete: every text the Connect window uses has an English and an Indonesian entry.
final class LocalizationCatalogTests: XCTestCase {
    private func catalog() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: projectFile("Resources/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(json["strings"] as? [String: [String: Any]])
    }

    private func value(_ entry: [String: Any], _ language: String) -> String? {
        ((entry["localizations"] as? [String: Any])?[language] as? [String: Any]).flatMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
    }

    func testEveryEntryHasEnglishAndIndonesian() throws {
        let strings = try catalog()
        XCTAssertGreaterThan(strings.count, 60)
        for (key, entry) in strings {
            XCTAssertFalse((value(entry, "en") ?? "").isEmpty, "\(key): missing English")
            XCTAssertFalse((value(entry, "id") ?? "").isEmpty, "\(key): missing Indonesian")
        }
    }

    func testEveryFriendlyErrorIsTranslated() throws {
        let strings = try catalog()
        for text in FriendlyErrors.allTexts { XCTAssertNotNil(strings[text].flatMap { value($0, "id") }, "Missing Indonesian text for: \(text)") }
    }

    func testTranslationsKeepTheirPlaceholders() throws {
        for (key, entry) in try catalog() {
            let placeholders = { (text: String) in text.components(separatedBy: "%").dropFirst().map { String($0.prefix(while: { $0.isLetter || $0 == "@" }).prefix(3)) }.sorted() }
            XCTAssertEqual(placeholders(key), placeholders(value(entry, "id") ?? ""), "\(key): the Indonesian text must keep the same placeholders")
        }
    }

    func testStringsUsedByTheCodeAreInTheCatalog() throws {
        let strings = try catalog()
        let roots = ["Packages/Features/Sources/WorkspaceFeature", "Packages/Features/Sources/SettingsFeature", "Packages/DesignSystem/Sources/Components"]
        let files = roots.flatMap { root -> [URL] in
            let folder = projectFile(root + "/.")
            return (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        }
        XCTAssertGreaterThan(files.count, 5)
        // Literals passed straight to the common SwiftUI text initialisers and to String(localized:).
        let pattern = try NSRegularExpression(pattern: #"(?:\b(?:Text|Button|Toggle|Menu|CommandMenu|Picker|Section|Label|SectionLabel|SettingsRow|SettingsCard|PresetCard|LabeledContent)\(|footer:|String\(localized:|\.help\(|\.accessibilityLabel\(|RailButton\(title:)\s*"([^"\\]+(?:\\.[^"\\]*)*)""#)
        var missing: Set<String> = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                var key = String(source[range])
                key = key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%lld", options: .regularExpression)
                // An interpolation may be a number (%lld) or text (%@); the catalog keeps whichever the type gives.
                if key.contains("%lld"), strings[key] == nil {
                    let shape = NSRegularExpression.escapedPattern(for: key).replacingOccurrences(of: "%lld", with: "(?:%lld|%@)")
                    if strings.keys.contains(where: { $0.range(of: "^" + shape + "$", options: .regularExpression) != nil }) { continue }
                }
                if key.contains("%lld") && !key.contains(" ") { continue } // "\(number)" alone
                if strings[key] == nil { missing.insert(key) }
            }
        }
        XCTAssertTrue(missing.isEmpty, "Not in Localizable.xcstrings: \(missing.sorted())")
    }
}

@MainActor
final class ConnectRenderTests: XCTestCase {
    private func render(_ status: ConnectStatus, name: String, settings: MirrorSettings = MirrorSettings(), appearance: NSAppearance.Name = .aqua) throws {
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        let model = AppModel(keymapRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                             defaults: isolatedDefaults())
        model.settings = settings
        let view = DeviceDetail(status: status, showsWireless: .constant(false)).environmentObject(model)
        let image = try renderSnapshot(view, size: CGSize(width: 560, height: 900), name: "connect-\(name)", appearance: appearance)
        XCTAssertFalse(isBlankImage(image))
    }

    func testEveryBannerRenders() throws {
        try render(ConnectStatus(banner: .noDevice, canStart: false, isStarting: false), name: "nodevice")
        try render(ConnectStatus(banner: .unauthorized, canStart: false, isStarting: false), name: "unauthorized")
        try render(ConnectStatus(banner: .offline, canStart: false, isStarting: false), name: "offline")
        try render(ConnectStatus(banner: .failed("adb: device '3A1F9C27' not found (exit code 1)"), canStart: true, isStarting: false), name: "failed")
        try render(ConnectStatus(banner: .adbMissing, canStart: false, isStarting: false), name: "adbmissing")
    }

    func testReadyWithObsOnRendersInBothAppearances() throws {
        var settings = MirrorSettings()
        settings.obsStreamEnabled = true
        settings.quality = try XCTUnwrap(VideoQuality.values(for: .gaming))
        try render(ConnectStatus(banner: nil, canStart: true, isStarting: false), name: "ready-light", settings: settings)
        try render(ConnectStatus(banner: nil, canStart: true, isStarting: false), name: "ready-dark", settings: settings, appearance: .darkAqua)
    }

    func testWirelessSheetRenders() throws {
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        let model = AppModel(keymapRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                             defaults: isolatedDefaults())
        let image = try renderSnapshot(WirelessSheet().environmentObject(model), size: CGSize(width: 460, height: 520), name: "connect-wireless")
        XCTAssertFalse(isBlankImage(image))
    }
}

/// A throw-away preferences store, so a test never changes what the app (or another test) remembers.
func isolatedDefaults() -> UserDefaults {
    let name = "benzmirror.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
