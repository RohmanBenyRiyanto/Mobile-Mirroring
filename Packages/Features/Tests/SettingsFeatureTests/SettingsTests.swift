import Components
import DomainModels
import SwiftUI
import TestSupport
import Theme
import XCTest
@testable import SettingsFeature
@testable import WorkspaceFeature

final class ShortcutCatalogTests: XCTestCase {
    func testNoTwoMenuItemsShareAShortcut() {
        let clashes = ShortcutCatalog.shared.conflicts()
        XCTAssertTrue(clashes.isEmpty, "shared: \(clashes.map { "\($0.key.display): \($0.value.map(\.title))" })")
    }

    func testShortcutsAreWrittenTheWayMacOSWritesThem() {
        XCTAssertEqual(KeyCombo("H", [.command, .shift]).display, "⇧⌘H")
        XCTAssertEqual(KeyCombo("Y", [.command, .option]).display, "⌥⌘Y")
        XCTAssertEqual(KeyCombo("Tab", [.control, .shift]).display, "⌃⇧Tab")
        XCTAssertEqual(KeyCombo("1", []).display, "1")
        XCTAssertEqual(KeyCombo("↩").display, "⌘↩")
    }

    func testMenuShortcutsMatchTheDesign() throws {
        func combo(_ id: String) throws -> String { try XCTUnwrap(ShortcutCatalog.shared.entries.first { $0.id == id }).combo.display }
        XCTAssertEqual(try combo("Mirror.Screenshot"), "⌘S")
        XCTAssertEqual(try combo("Mirror.Start Recording"), "⇧⌘R")
        XCTAssertEqual(try combo("Device.Home"), "⇧⌘H")
        XCTAssertEqual(try combo("View.Stream Mode"), "⇧⌘B")
        XCTAssertEqual(try combo("View.Statistics"), "⌘I")
        XCTAssertEqual(try combo("Device.Logcat"), "⇧⌘L")
        XCTAssertEqual(try combo("Device.UI Inspector"), "⌥⌘I")
        XCTAssertEqual(try combo("Keymap.Record Macro"), "7")
    }

    func testSearchFindsByNameShortcutAndMenu() {
        let catalog = ShortcutCatalog.shared
        XCTAssertEqual(catalog.filtered(by: "").count, catalog.entries.count)
        XCTAssertTrue(catalog.filtered(by: "screenshot").contains { $0.title == "Screenshot" })
        XCTAssertTrue(catalog.filtered(by: "⇧⌘b").contains { $0.title == "Stream Mode" })
        XCTAssertTrue(catalog.filtered(by: "keymap").allSatisfy { $0.menu == "Keymap" || $0.title.lowercased().contains("keymap") })
        XCTAssertTrue(catalog.filtered(by: "no such thing").isEmpty)
    }

    func testAConflictIsReportedForBothEntries() {
        let a = ShortcutCatalog.Entry(id: "a", title: "A", menu: "M", combo: KeyCombo("I"))
        let b = ShortcutCatalog.Entry(id: "b", title: "B", menu: "M", combo: KeyCombo("I"))
        XCTAssertEqual(ShortcutCatalog(entries: [a, b]).conflicts().first?.value.count, 2)
        XCTAssertEqual(ShortcutCatalog(entries: [a, b]).conflict(of: a), b)
        XCTAssertNil(ShortcutCatalog(entries: [a]).conflict(of: a))
    }

    func testEveryShortcutNameIsTranslated() throws {
        let data = try Data(contentsOf: projectFile("Resources/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        for entry in ShortcutCatalog.shared.entries {
            XCTAssertNotNil(strings[entry.title], "\(entry.title) has no entry in the string catalog")
        }
    }
}

final class FolderChoiceTests: XCTestCase {
    func testDefaultFoldersAreShownWithTheHomeFolderAsTilde() {
        XCTAssertEqual(FolderChoice.displayPath(nil, fallback: .picturesDirectory), "~/Pictures/\(AppInfo.name)")
        XCTAssertEqual(FolderChoice.displayPath(nil, fallback: .moviesDirectory), "~/Movies/\(AppInfo.name)")
    }

    func testAChosenFolderIsShownAsChosen() {
        XCTAssertEqual(FolderChoice.displayPath("/Volumes/Disk/Captures", fallback: .picturesDirectory), "/Volumes/Disk/Captures")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(FolderChoice.displayPath(home + "/Desktop/Shots", fallback: .picturesDirectory), "~/Desktop/Shots")
    }
}

final class SettingsPersistenceTests: XCTestCase {
    func testNewSettingsLoadFromOldSavedOnes() throws {
        let old = Data(#"{"audioEnabled":false,"obsStreamPort":9000}"#.utf8)
        let settings = try JSONDecoder().decode(MirrorSettings.self, from: old)
        XCTAssertFalse(settings.audioEnabled)
        XCTAssertEqual(settings.obsStreamPort, 9000)
        XCTAssertFalse(settings.mirrorOnConnect)
        XCTAssertNil(settings.screenshotFolder)
        XCTAssertNil(settings.recordingFolder)
    }

    func testFoldersRoundTrip() throws {
        var settings = MirrorSettings()
        settings.mirrorOnConnect = true
        settings.screenshotFolder = "/tmp/shots"
        let copy = try JSONDecoder().decode(MirrorSettings.self, from: try JSONEncoder().encode(settings))
        XCTAssertEqual(copy, settings)
    }

    func testOutputFilesUseTheChosenFolderOnlyWhenItExists() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let chosen = try OutputFiles.newURL(in: .picturesDirectory, prefix: "Shot", pathExtension: "png", custom: folder.path)
        XCTAssertEqual(chosen.deletingLastPathComponent().path, folder.path)
        // A missing or relative folder falls back to the default instead of creating something unexpected.
        let missing = try OutputFiles.newURL(in: .picturesDirectory, prefix: "Shot", pathExtension: "png", custom: "/no/such/folder")
        XCTAssertTrue(missing.path.contains("/Pictures/\(AppInfo.name)/"), missing.path)
        let relative = try OutputFiles.newURL(in: .picturesDirectory, prefix: "Shot", pathExtension: "png", custom: "Documents")
        XCTAssertTrue(relative.path.contains("/Pictures/\(AppInfo.name)/"))
    }
}

@MainActor
final class SettingsRenderTests: XCTestCase {
    func testEveryTabRendersInBothAppearances() throws {
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        let defaults = isolatedDefaults()
        let appearance = AppearanceStore(defaults: defaults, apply: { _ in })
        let model = AppModel(keymapRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                             defaults: defaults, appearance: appearance)
        let tabs: [(String, AnyView)] = [
            ("general", AnyView(GroupedForm { GeneralTab(model: model, appearance: appearance) })),
            ("video", AnyView(GroupedForm { VideoTab(model: model) })),
            ("audio", AnyView(GroupedForm { AudioTab(model: model) })),
            ("rail", AnyView(GroupedForm { RailTab(model: model) })),
            ("shortcuts", AnyView(GroupedForm { ShortcutsTab(model: model) })),
            ("advanced", AnyView(GroupedForm { AdvancedTab(model: model, appearance: appearance) })),
        ]
        for (name, view) in tabs {
            for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
                let image = try renderSnapshot(view, size: CGSize(width: 560, height: 480), name: "settings-\(name)-\(appearanceName == .aqua ? "light" : "dark")", appearance: appearanceName)
                XCTAssertFalse(isBlankImage(image), name)
            }
        }
    }
}

func isolatedDefaults() -> UserDefaults {
    let name = "benzmirror.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

final class ShortcutBookTests: XCTestCase {
    func testAChangedShortcutIsUsedAndSurvivesSaving() throws {
        var book = ShortcutBook()
        XCTAssertEqual(book.combo(for: "Mirror.Screenshot")?.display, "⌘S")
        book.set(KeyCombo("S", [.command, .option]), for: "Mirror.Screenshot")
        book.set(nil, for: "Device.Home") // removed
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "benz-shortcut-test"))
        defer { defaults.removePersistentDomain(forName: "benz-shortcut-test") }
        book.save(to: defaults)
        let loaded = ShortcutBook.load(from: defaults)
        XCTAssertEqual(loaded.combo(for: "Mirror.Screenshot")?.display, "⌥⌘S")
        XCTAssertNil(loaded.combo(for: "Device.Home"), "a removed shortcut stays removed")
        XCTAssertTrue(loaded.isChanged("Device.Home"))
    }

    func testSettingTheOriginalShortcutClearsTheChange() {
        var book = ShortcutBook()
        book.set(KeyCombo("S", [.command, .option]), for: "Mirror.Screenshot")
        book.set(KeyCombo("S"), for: "Mirror.Screenshot")
        XCTAssertFalse(book.isChanged("Mirror.Screenshot"))
    }

    func testConflictsAreFoundAgainstChangedShortcutsToo() {
        var book = ShortcutBook()
        XCTAssertEqual(book.conflict(for: KeyCombo("S"), excluding: "Device.Home")?.id, "Mirror.Screenshot")
        book.set(KeyCombo("S", [.command, .option]), for: "Mirror.Screenshot")
        XCTAssertNil(book.conflict(for: KeyCombo("S"), excluding: "Device.Home"), "the old combination is free after a change")
        XCTAssertEqual(book.conflict(for: KeyCombo("S", [.command, .option]), excluding: "Device.Home")?.id, "Mirror.Screenshot")
        XCTAssertNil(book.conflict(for: KeyCombo("S"), excluding: "Mirror.Screenshot"))
    }

    func testReservedShortcutsAreRefused() {
        XCTAssertTrue(ShortcutRegistry.reserved.contains(KeyCombo("Q")))
        XCTAssertTrue(ShortcutRegistry.reserved.contains(KeyCombo("C")))
        XCTAssertFalse(ShortcutRegistry.items.contains { ShortcutRegistry.reserved.contains($0.original) }, "no original menu shortcut collides with a reserved one")
    }
}

final class LanguageCompletenessTests: XCTestCase {
    private func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:lld|ld|d|@|f|\\.\\df|s|u)")
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).map { String(text[Range($0.range, in: text)!]) }.sorted()
    }

    /// Every language offered in Settings has every string, and keeps the same %@ and %lld as the English text.
    func testEveryOfferedLanguageIsComplete() throws {
        let data = try Data(contentsOf: projectFile("Resources/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        for language in AppLanguage.supported where language.code != "en" {
            var missing: [String] = [], mismatched: [String] = []
            for (key, entry) in strings {
                let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
                let english = ((localizations["en"]?["stringUnit"] as? [String: Any])?["value"] as? String) ?? key
                guard let translated = (localizations[language.code]?["stringUnit"] as? [String: Any])?["value"] as? String else { missing.append(key); continue }
                if placeholders(english) != placeholders(translated) { mismatched.append(key) }
            }
            XCTAssertTrue(missing.isEmpty, "\(language.code) is missing \(missing.count) strings, for example \(missing.prefix(3))")
            XCTAssertTrue(mismatched.isEmpty, "\(language.code) changed the placeholders of \(mismatched.prefix(3))")
        }
    }

    func testTheInfoFileListsEveryLanguage() throws {
        let plist = try XCTUnwrap(NSDictionary(contentsOf: projectFile("Resources/Info.plist")))
        let listed = Set(plist["CFBundleLocalizations"] as? [String] ?? [])
        XCTAssertEqual(listed, Set(AppLanguage.supported.map(\.code)))
    }
}
