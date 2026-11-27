import AppKit
import XCTest
import FeatureTestSupport
import TestSupport
@testable import DomainModels
@testable import Persistence
@testable import WorkspaceFeature

private func button(_ key: UInt16 = 12) -> KeymapElement {
    KeymapElement(position: NormalizedPoint(x: 0.5, y: 0.5), action: .button(key: key, mode: .tap))
}

private func macro(steps: Int, seconds: Double) -> KeymapElement {
    let list = (0..<steps).map { MacroStep(time: seconds * Double($0) / Double(max(steps - 1, 1)), kind: $0 == steps - 1 ? .up : ($0 == 0 ? .down : .move),
                                           finger: 0, position: NormalizedPoint(x: 0.5, y: 0.5)) }
    return KeymapElement(label: "Combo", position: NormalizedPoint(x: 0.5, y: 0.5), action: .macro(key: 13, steps: list, loop: false, speed: 1))
}

final class KeymapSummaryTests: XCTestCase {
    private func summary(_ keymap: Keymap, id: String = "x", existing: Set<String> = []) -> KeymapSummary {
        KeymapSummary(profile: Profile(id: id, name: "Shared", payload: keymap), existingIDs: existing)
    }

    func testCountsEachKindOfElementInAFixedOrder() {
        let aim = KeymapElement(position: NormalizedPoint(x: 0.7, y: 0.5), action: .aim(toggleKey: 50, sensitivity: 2, radius: 0.1))
        let stick = KeymapElement(position: NormalizedPoint(x: 0.2, y: 0.7), action: .joystick(up: 13, left: 0, down: 1, right: 2, radius: 0.1, response: 0.1))
        let s = summary(Keymap(elements: [button(), button(14), stick, aim]))
        XCTAssertEqual(s.counts.map(\.kind), ["Buttons", "Joysticks", "Free-look"])
        XCTAssertEqual(s.counts.map(\.count), [2, 1, 1])
        XCTAssertTrue(s.message.contains("2 buttons, 1 joysticks, 1 free-look"))
    }

    func testAPlainKeymapHasNoWarnings() {
        let s = summary(Keymap(elements: [button()]))
        XCTAssertEqual(s.warnings, [])
        XCTAssertEqual(s.message, "1 buttons.")
        XCTAssertTrue(summary(Keymap()).message.contains("No elements"))
    }

    func testMacrosAreCalledOutWithTheirSizeBecauseTheyReplayTouches() {
        let s = summary(Keymap(elements: [macro(steps: 40, seconds: 1.5), macro(steps: 10, seconds: 0.5)]))
        XCTAssertEqual(s.macroCount, 2)
        XCTAssertEqual(s.macroSteps, 50)
        XCTAssertEqual(s.macroSeconds, 2.0, accuracy: 1e-9)
        XCTAssertTrue(s.warnings.contains { $0.contains("2 macros") && $0.contains("50 recorded touches") && $0.contains("replay on your phone") })
    }

    func testAGamePackageWarnsThatTheKeymapSwitchesItselfOn() {
        let s = summary(Keymap(package: "com.tencent.ig", elements: [button()]))
        XCTAssertTrue(s.warnings.contains { $0.contains("com.tencent.ig") && $0.contains("by itself") })
    }

    func testFreeLookWarnsAboutThePointer() {
        let aim = KeymapElement(position: NormalizedPoint(x: 0.7, y: 0.5), action: .aim(toggleKey: 50, sensitivity: 2, radius: 0.1))
        XCTAssertTrue(summary(Keymap(elements: [aim])).warnings.contains { $0.contains("pointer") })
    }

    func testANameThatIsTakenIsSavedAsACopy() {
        let s = summary(Keymap(), id: "pubg", existing: ["pubg", "pubg-2"])
        XCTAssertEqual(s.savedAs, "pubg-3")
        XCTAssertTrue(s.warnings.contains { $0.contains("pubg-3") && $0.contains("nothing is replaced") })
        XCTAssertNil(summary(Keymap(), id: "fresh", existing: ["pubg"]).savedAs)
    }

    /// The app shell declares the file type in `project.yml` (which generates the Info.plist).
    func testFileTypeDeclarationsMatchTheAppShell() throws {
        let spec = try String(contentsOf: projectFile("project.yml"), encoding: .utf8)
        XCTAssertTrue(spec.contains(KeymapFile.typeIdentifier), "the app must declare the type it exports")
        XCTAssertTrue(spec.contains("public.filename-extension: [\(KeymapFile.fileExtension)]"))
        XCTAssertTrue(spec.contains("CFBundleDocumentTypes"))
        XCTAssertTrue(spec.contains("UTExportedTypeDeclarations"))
        XCTAssertTrue(KeymapFile.contentTypes.count >= 1)
    }
}

@MainActor
final class KeymapImportFlowTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(answer: Bool = true) -> (AppModel, Asked) {
        let model = AppModel(keymapRoot: root.appendingPathComponent("store"), cursorCapture: FakeCursorCapture())
        let asked = Asked()
        model.confirmKeymapImport = { summary in
            asked.summaries.append(summary)
            return answer
        }
        return (model, asked)
    }

    private final class Asked {
        var summaries: [KeymapSummary] = []
    }

    /// A shared keymap, as another person's copy of the app would export it.
    private func sharedFile(id: String = "friend", name: String = "Friend's keymap", package: String? = "com.game.one", elements: [KeymapElement]? = nil) throws -> Data {
        let other = try ProfileStore<Keymap>(kind: "keymap", root: root.appendingPathComponent("friend-store"))
        try other.save(Profile(id: id, name: name, payload: Keymap(package: package, elements: elements ?? [button(), macro(steps: 5, seconds: 1)])))
        return try other.exportData(id: id)
    }

    func testTheUserSeesWhatIsInsideBeforeAnythingIsSaved() throws {
        let (model, asked) = makeModel(answer: false)
        XCTAssertFalse(model.importKeymap(data: try sharedFile(), source: "test"))

        let summary = try XCTUnwrap(asked.summaries.first)
        XCTAssertEqual(summary.name, "Friend's keymap")
        XCTAssertEqual(summary.macroCount, 1)
        XCTAssertEqual(summary.package, "com.game.one")
        XCTAssertTrue(model.keymapProfiles.isEmpty, "declining must save nothing")
        XCTAssertEqual(model.notice, "Import cancelled")
        XCTAssertEqual(model.keymapStore?.identifiers(), [])
    }

    func testAgreeingSavesTheKeymapAndIndexesItsGame() throws {
        let (model, _) = makeModel()
        XCTAssertTrue(model.importKeymap(data: try sharedFile(), source: "friend.benzkeymap"))
        XCTAssertEqual(model.keymapProfiles.map(\.name), ["Friend's keymap"])
        XCTAssertEqual(model.keymapPackageIndex, ["com.game.one": "friend"], "so it can switch on by itself for that game")
        XCTAssertEqual(model.notice, "Imported Friend's keymap from friend.benzkeymap")
    }

    func testImportingTwiceKeepsBothAndNeverOverwrites() throws {
        let (model, asked) = makeModel()
        let file = try sharedFile()
        XCTAssertTrue(model.importKeymap(data: file, source: "a"))
        XCTAssertTrue(model.importKeymap(data: file, source: "b"))
        XCTAssertEqual(Set(model.keymapStore?.identifiers() ?? []), ["friend", "friend-2"])
        XCTAssertEqual(asked.summaries.last?.savedAs, "friend-2", "the user is told before it happens")
    }

    func testAFileWithBrokenContentIsRefusedWithoutAsking() throws {
        let (model, asked) = makeModel()
        let joystickWithRepeatedKeys = KeymapElement(position: NormalizedPoint(x: 0.2, y: 0.7),
                                                     action: .joystick(up: 13, left: 13, down: 1, right: 2, radius: 0.1, response: 0.1))
        XCTAssertFalse(model.importKeymap(data: try sharedFile(elements: [joystickWithRepeatedKeys]), source: "evil"))
        XCTAssertTrue(asked.summaries.isEmpty, "nothing unusable is even offered")
        XCTAssertTrue(model.notice?.hasPrefix("Import failed") == true)
        XCTAssertEqual(model.keymapStore?.identifiers(), [])
    }

    func testNonsenseAndOversizedInputIsRefused() throws {
        let (model, asked) = makeModel()
        XCTAssertFalse(model.importKeymap(data: Data("not a keymap".utf8), source: "x"))
        XCTAssertFalse(model.importKeymap(data: Data(repeating: 0x20, count: ProfileFormat.maxBytes + 1), source: "x"))
        XCTAssertFalse(model.importKeymap(data: Data(#"{"format":"benzmirror.profile","version":1,"kind":"keymap","id":"../../escape","name":"x","modified":"2026-11-27T10:00:00Z","payload":{"elements":[]}}"#.utf8), source: "x"))
        XCTAssertTrue(asked.summaries.isEmpty)
        XCTAssertEqual(model.keymapStore?.identifiers(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.json").path))
    }

    func testAKeymapFromAnotherKindOfProfileIsRefused() throws {
        let (model, _) = makeModel()
        let macros = try ProfileStore<Keymap>(kind: "macro", root: root.appendingPathComponent("other"))
        try macros.save(Profile(id: "m", name: "M", payload: Keymap()))
        XCTAssertFalse(model.importKeymap(data: try macros.exportData(id: "m"), source: "x"))
        XCTAssertTrue(model.notice?.contains("macro") == true)
    }

    // MARK: Entry points

    func testFilesAreImportedFromDisk() throws {
        let (model, _) = makeModel()
        let file = root.appendingPathComponent("friend.benzkeymap")
        try sharedFile().write(to: file)
        model.importKeymap(from: file)
        XCTAssertEqual(model.keymapProfiles.count, 1)

        model.importKeymap(from: root.appendingPathComponent("missing.benzkeymap"))
        XCTAssertTrue(model.notice?.hasPrefix("Import failed") == true)
    }

    func testADroppedKeymapIsImportedNotSentToThePhone() throws {
        let (model, asked) = makeModel()
        let file = root.appendingPathComponent("dropped.benzkeymap")
        try sharedFile().write(to: file)
        model.handleDrop([file])
        XCTAssertEqual(asked.summaries.count, 1)
        XCTAssertEqual(model.keymapProfiles.count, 1)
    }

    func testAPlainJSONFileDroppedOnTheMirrorStillGoesToThePhone() throws {
        let (model, asked) = makeModel()
        let file = root.appendingPathComponent("notes.json")
        try sharedFile().write(to: file)
        model.handleDrop([file]) // no phone is selected here, so the copy is simply skipped
        XCTAssertTrue(asked.summaries.isEmpty, "only .benzkeymap files are treated as keymaps")
    }

    func testKeymapsTravelThroughTheClipboard() throws {
        let (model, _) = makeModel()
        XCTAssertTrue(model.importKeymap(data: try sharedFile(), source: "x"))

        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { board.releaseGlobally() }
        model.copyKeymapToClipboard(id: "friend", pasteboard: board)
        let text = try XCTUnwrap(board.string(forType: .string))
        XCTAssertTrue(text.contains("benzmirror.profile"))

        let (other, _) = { () -> (AppModel, Asked) in
            let model = AppModel(keymapRoot: root.appendingPathComponent("second"), cursorCapture: FakeCursorCapture())
            let asked = Asked()
            model.confirmKeymapImport = { asked.summaries.append($0); return true }
            return (model, asked)
        }()
        other.importKeymapFromClipboard(pasteboard: board)
        XCTAssertEqual(other.keymapProfiles.map(\.name), ["Friend's keymap"])
    }

    func testTheClipboardImportRefusesEmptyAndHugeText() {
        let (model, asked) = makeModel()
        let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { board.releaseGlobally() }

        model.importKeymapFromClipboard(pasteboard: board)
        XCTAssertEqual(model.notice, "The clipboard has no text to import")

        board.clearContents()
        board.setString(String(repeating: "a", count: ProfileFormat.maxBytes + 1), forType: .string)
        model.importKeymapFromClipboard(pasteboard: board)
        XCTAssertTrue(model.notice?.hasPrefix("Import failed") == true)
        XCTAssertTrue(asked.summaries.isEmpty)
    }

    func testFilesOpenedFromFinderWaitForTheAppToBeReady() {
        let inbox = FileOpenInbox()
        let first = URL(fileURLWithPath: "/tmp/a.benzkeymap"), second = URL(fileURLWithPath: "/tmp/b.benzkeymap")
        inbox.receive([first]) // arrives while the app is still starting

        var received: [URL] = []
        inbox.handler = { received += $0 }
        XCTAssertEqual(received, [first], "handed over as soon as the app is ready")

        inbox.receive([second])
        XCTAssertEqual(received, [first, second])
    }
}
