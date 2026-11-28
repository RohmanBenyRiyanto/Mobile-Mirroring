import DomainModels
import Networking
import Persistence
import TestSupport
import XCTest
@testable import WorkspaceFeature

final class PhoneTabTests: XCTestCase {
    func testMirroredPhonesFirstThenOfflineOnes() {
        let tabs = PhoneTab.tabs(
            mirrored: [("A", "Pixel", true), ("B", "", false)],
            devices: [AndroidDevice(serial: "A", state: .device, model: nil), AndroidDevice(serial: "C", state: .offline, model: "Galaxy_S"),
                      AndroidDevice(serial: "D", state: .device, model: "Other")],
            activeSerial: "B")
        XCTAssertEqual(tabs.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(tabs[1].title, "B")
        XCTAssertTrue(tabs[1].isActive)
        XCTAssertTrue(tabs[0].isRecording)
        XCTAssertTrue(tabs[2].isOffline)
        XCTAssertEqual(tabs[2].title, "Galaxy S")
    }
}

final class ExampleKeymapTests: XCTestCase {
    func testEveryShippedKeymapLoadsAndValidates() throws {
        let folder = projectFile("docs/examples/.")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == KeymapFile.fileExtension }
        XCTAssertFalse(files.isEmpty)
        let store = try ProfileStore<Keymap>(kind: "keymap", root: FileManager.default.temporaryDirectory.appendingPathComponent("examples-\(UUID().uuidString)"))
        for file in files {
            let profile = try store.inspect(Data(contentsOf: file))
            XCTAssertNoThrow(try profile.payload.validated(), file.lastPathComponent)
            XCTAssertFalse(profile.payload.elements.isEmpty)
        }
    }

    func testMagicChessKeysDoNotCollide() throws {
        let store = try ProfileStore<Keymap>(kind: "keymap", root: FileManager.default.temporaryDirectory.appendingPathComponent("mc-\(UUID().uuidString)"))
        let profile = try store.inspect(Data(contentsOf: projectFile("docs/examples/magic-chess-gogo.benzkeymap")))
        XCTAssertEqual(profile.payload.package, "com.mobilechess.gp")
        let keys: [UInt16] = profile.payload.elements.flatMap { $0.keys }
        XCTAssertEqual(keys.count, Set(keys).count)
        XCTAssertEqual(profile.payload.elements.count, 18)
        XCTAssertEqual(profile.payload.key(for: .buttonA), 23, "the controller buys the fifth card with A")
    }
}

@MainActor
final class BundledKeymapSeedTests: XCTestCase {
    func testSeededOnceAndNeverRestoredAfterDeletion() throws {
        let store = try ProfileStore<Keymap>(kind: "keymap", root: FileManager.default.temporaryDirectory.appendingPathComponent("seed-\(UUID().uuidString)"))
        let folder = projectFile("Resources/DefaultKeymaps/.")
        let defaults = isolatedDefaults()
        AppModel.seedBundledKeymaps(into: store, defaults: defaults, folder: folder)
        XCTAssertTrue(store.contains(id: "magic-chess-gogo"))

        try store.delete(id: "magic-chess-gogo")
        AppModel.seedBundledKeymaps(into: store, defaults: defaults, folder: folder)
        XCTAssertFalse(store.contains(id: "magic-chess-gogo"), "a deleted keymap stays deleted")
    }
}
