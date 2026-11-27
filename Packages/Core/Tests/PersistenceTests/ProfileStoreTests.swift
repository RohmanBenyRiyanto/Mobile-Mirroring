import XCTest
@testable import Persistence

final class ProfileStoreTests: XCTestCase {
    private struct Sample: Codable, Equatable {
        var buttons: [String]
        var radius: Double
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore(kind: String = "keymap") throws -> ProfileStore<Sample> {
        try ProfileStore<Sample>(kind: kind, root: root)
    }

    private func profile(_ id: String = "com.tencent.ig", name: String = "PUBG Mobile") -> Profile<Sample> {
        Profile(id: id, name: name, payload: Sample(buttons: ["W", "A", "S", "D"], radius: 0.15))
    }

    // MARK: Save and load

    func testSaveThenLoadRoundTrips() throws {
        let store = try makeStore()
        let saved = try store.save(profile())
        let loaded = try store.load(id: "com.tencent.ig")
        XCTAssertEqual(loaded.id, "com.tencent.ig")
        XCTAssertEqual(loaded.name, "PUBG Mobile")
        XCTAssertEqual(loaded.payload, profile().payload)
        XCTAssertEqual(loaded.modified.timeIntervalSince1970, saved.modified.timeIntervalSince1970, accuracy: 1)
    }

    func testSavingAgainReplacesTheProfile() throws {
        let store = try makeStore()
        try store.save(profile())
        var changed = profile()
        changed.payload.radius = 0.4
        try store.save(changed)
        XCTAssertEqual(try store.load(id: "com.tencent.ig").payload.radius, 0.4)
        XCTAssertEqual(store.list().count, 1)
    }

    func testFilesAreStoredInTheKindFolderAndReadableOnlyByTheUser() throws {
        try makeStore().save(profile())
        let file = root.appendingPathComponent("keymap/com.tencent.ig.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? Int
        XCTAssertEqual(folder, 0o700)
    }

    func testListIsSortedByNameAndSkipsDamagedFiles() throws {
        let store = try makeStore()
        try store.save(profile("b.game", name: "banana"))
        try store.save(profile("a.game", name: "Apple"))
        try store.save(profile("c.game", name: "cherry"))
        try Data("{ not json".utf8).write(to: root.appendingPathComponent("keymap/broken.json"))
        try Data("ignored".utf8).write(to: root.appendingPathComponent("keymap/readme.txt"))

        XCTAssertEqual(store.list().map(\.name), ["Apple", "banana", "cherry"])
    }

    func testDeleteRemovesTheProfile() throws {
        let store = try makeStore()
        try store.save(profile())
        try store.delete(id: "com.tencent.ig")
        XCTAssertEqual(store.list(), [])
        XCTAssertThrowsError(try store.load(id: "com.tencent.ig")) { XCTAssertEqual($0 as? ProfileError, .notFound("com.tencent.ig")) }
        XCTAssertThrowsError(try store.delete(id: "com.tencent.ig"))
    }

    func testNamesAreCleaned() throws {
        let saved = try makeStore().save(profile(name: "  Evil\u{1B}[31m\nName  "))
        XCTAssertEqual(saved.name, "Evil[31mName")
        XCTAssertEqual(try makeStore().save(profile("empty.name", name: " \n ")).name, "empty.name", "falls back to the id")
        XCTAssertEqual(try makeStore().save(profile("long.name", name: String(repeating: "x", count: 500))).name.count, ProfileFormat.maxNameLength)
    }

    // MARK: Identifiers (security)

    func testIdentifiersThatCouldEscapeTheFolderAreRejected() throws {
        let store = try makeStore()
        for bad in ["", ".hidden", "..", "../evil", "a/b", "a\\b", "a b", "a;b", "$(id)", "é", "a..b", String(repeating: "x", count: 129), "x\u{0}y"] {
            XCTAssertFalse(ProfileFormat.isValidIdentifier(bad), bad)
            XCTAssertThrowsError(try store.save(profile(bad)), bad)
            XCTAssertThrowsError(try store.load(id: bad), bad)
            XCTAssertThrowsError(try store.delete(id: bad), bad)
        }
        XCTAssertThrowsError(try ProfileStore<Sample>(kind: "../etc", root: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("evil.json").path))
    }

    func testRealPackageNamesAndSimpleNamesAreValid() {
        for good in ["com.tencent.ig", "default", "my-profile_2", "a.b"] { XCTAssertTrue(ProfileFormat.isValidIdentifier(good), good) }
    }

    // MARK: Export and import

    func testExportThenImportIntoAnotherStoreKeepsEverything() throws {
        let source = try makeStore()
        try source.save(profile())
        let data = try source.exportData(id: "com.tencent.ig")

        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"format\" : \"benzmirror.profile\""))
        XCTAssertTrue(text.contains("\"version\" : 1"))

        let other = try ProfileStore<Sample>(kind: "keymap", root: root.appendingPathComponent("elsewhere"))
        let imported = try other.importData(data)
        XCTAssertEqual(imported.id, "com.tencent.ig")
        XCTAssertEqual(imported.payload, profile().payload)
        XCTAssertEqual(other.list().map(\.id), ["com.tencent.ig"])
    }

    func testImportingAnExistingIdMakesACopyUnlessOverwriting() throws {
        let store = try makeStore()
        try store.save(profile())
        let data = try store.exportData(id: "com.tencent.ig")

        XCTAssertEqual(try store.importData(data).id, "com.tencent.ig-2")
        XCTAssertEqual(try store.importData(data).id, "com.tencent.ig-3")
        XCTAssertEqual(try store.importData(data, overwrite: true).id, "com.tencent.ig")
        XCTAssertEqual(store.list().count, 3)
    }

    func testImportRejectsOversizedFilesBeforeParsing() throws {
        let huge = Data(repeating: 0x20, count: ProfileFormat.maxBytes + 1)
        XCTAssertThrowsError(try makeStore().importData(huge)) { XCTAssertEqual($0 as? ProfileError, .tooLarge) }
    }

    func testImportRejectsFilesThatAreNotProfiles() throws {
        let store = try makeStore()
        for text in ["", "not json", "[]", "{}", #"{"format":"something.else","version":1,"kind":"keymap"}"#] {
            XCTAssertThrowsError(try store.importData(Data(text.utf8)), text) { XCTAssertEqual($0 as? ProfileError, .notAProfile, text) }
        }
    }

    func testImportRejectsTheWrongKindAndNewerVersions() throws {
        let store = try makeStore()
        let other = try ProfileStore<Sample>(kind: "macro", root: root)
        try other.save(profile())
        let macro = try other.exportData(id: "com.tencent.ig")
        XCTAssertThrowsError(try store.importData(macro)) {
            XCTAssertEqual($0 as? ProfileError, .wrongKind(expected: "keymap", found: "macro"))
        }

        try store.save(profile())
        let exported = String(decoding: try store.exportData(id: "com.tencent.ig"), as: UTF8.self)
        let future = exported.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        XCTAssertNotEqual(future, exported, "the test must actually change the version")
        XCTAssertThrowsError(try store.importData(Data(future.utf8))) { XCTAssertEqual($0 as? ProfileError, .newerVersion(99)) }
    }

    func testImportRejectsAMaliciousIdAndNeverWritesOutsideTheFolder() throws {
        let store = try makeStore()
        let hostile = """
        {"format":"benzmirror.profile","version":1,"kind":"keymap","id":"../../escape","name":"x",
         "modified":"2026-11-27T10:00:00Z","payload":{"buttons":[],"radius":1}}
        """
        XCTAssertThrowsError(try store.importData(Data(hostile.utf8))) {
            XCTAssertEqual($0 as? ProfileError, .invalidIdentifier("../../escape"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.json").path))
    }

    func testImportReportsWhichFieldIsWrong() throws {
        let bad = """
        {"format":"benzmirror.profile","version":1,"kind":"keymap","id":"ok","name":"x",
         "modified":"2026-11-27T10:00:00Z","payload":{"buttons":"not a list","radius":1}}
        """
        XCTAssertThrowsError(try makeStore().importData(Data(bad.utf8))) { error in
            guard case let ProfileError.corrupt(detail) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(detail.contains("buttons"), detail)
        }
    }

    func testErrorsAreReadable() {
        XCTAssertTrue(ProfileError.newerVersion(2).localizedDescription.contains("newer version"))
        XCTAssertTrue(ProfileError.wrongKind(expected: "keymap", found: "macro").localizedDescription.contains("macro"))
    }
}
