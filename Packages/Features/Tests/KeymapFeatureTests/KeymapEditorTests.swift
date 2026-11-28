import XCTest
@testable import DomainModels
@testable import KeymapFeature
@testable import Persistence

@MainActor
final class KeymapEditorModelTests: XCTestCase {
    private func newEditor() -> KeymapEditorModel { KeymapEditorModel(profile: nil) }

    func testAStartsEmptyAndCleanAndCanBeOpenedFromAProfile() {
        let editor = newEditor()
        XCTAssertEqual(editor.keymap.elements, [])
        XCTAssertEqual(editor.name, "My keymap")
        XCTAssertNil(editor.profileID)
        XCTAssertFalse(editor.isDirty)

        let keymap = Keymap(package: "com.tencent.ig", elements: [KeymapElement(label: "A", position: NormalizedPoint(x: 0.1, y: 0.1), action: .button(key: 12, mode: .tap))])
        let opened = KeymapEditorModel(profile: Profile(id: "pubg", name: "PUBG", payload: keymap))
        XCTAssertEqual(opened.keymap, keymap)
        XCTAssertEqual(opened.name, "PUBG")
        XCTAssertEqual(opened.package, "com.tencent.ig")
        XCTAssertEqual(opened.profileID, "pubg")
        XCTAssertFalse(opened.isDirty)
    }

    func testEachKindOfElementCanBeAddedWithSensibleDefaults() throws {
        let editor = newEditor()
        for kind in KeymapEditorModel.ElementKind.allCases { editor.add(kind) }
        XCTAssertEqual(editor.keymap.elements.count, KeymapEditorModel.ElementKind.allCases.count)
        XCTAssertNoThrow(try editor.validatedKeymap(), "everything the editor creates must pass validation")
        XCTAssertTrue(editor.isDirty)
        XCTAssertNotNil(editor.selection)
    }

    func testNewButtonsGetKeysThatNothingElseUses() {
        let editor = newEditor()
        let first = editor.add(.button), second = editor.add(.button), skill = editor.add(.skillShot)
        let keys = [first, second, skill].compactMap { editor.element($0)?.keys.first }
        XCTAssertEqual(Set(keys).count, 3, "\(keys)")
        XCTAssertEqual(KeymapEditorModel.freeKey(avoiding: [12, 14, 15]), 3)
        XCTAssertEqual(KeymapEditorModel.freeKey(avoiding: Set(0...200)), 12, "falls back rather than failing")
    }

    func testThereIsOnlyOneFreeLookArea() {
        let editor = newEditor()
        let first = editor.add(.freeLook)
        editor.selection = nil
        let second = editor.add(.freeLook)
        XCTAssertEqual(first, second)
        XCTAssertEqual(editor.keymap.elements.count, 1)
        XCTAssertEqual(editor.selection, first, "asking again selects the one that exists")
        XCTAssertNil(editor.duplicate(first), "and it cannot be duplicated")
    }

    func testMovingKeepsTheElementOnTheScreen() throws {
        let editor = newEditor()
        let id = editor.add(.button)
        editor.checkpoint()
        editor.move(id, to: NormalizedPoint(x: 1.5, y: -0.3))
        XCTAssertEqual(editor.element(id)?.position, NormalizedPoint(x: 1, y: 0))
        editor.moveHero(of: id, to: NormalizedPoint(x: 0.4, y: 0.4))
        XCTAssertEqual(editor.element(id)?.position, NormalizedPoint(x: 1, y: 0))
    }

    func testTheHeroOfASkillShotCanBeMoved() throws {
        let editor = newEditor()
        let id = editor.add(.skillShot)
        editor.moveHero(of: id, to: NormalizedPoint(x: 0.3, y: 2))
        guard case let .skillShot(_, _, _, _, hero) = try XCTUnwrap(editor.element(id)).action else { return XCTFail() }
        XCTAssertEqual(hero, NormalizedPoint(x: 0.3, y: 1))
    }

    func testDuplicateMakesAnOffsetCopyWithANewIdentity() throws {
        let editor = newEditor()
        let original = editor.add(.button)
        let copy = try XCTUnwrap(editor.duplicate(original))
        XCTAssertNotEqual(original, copy)
        XCTAssertEqual(editor.keymap.elements.count, 2)
        XCTAssertEqual(try XCTUnwrap(editor.element(copy)).position.x, try XCTUnwrap(editor.element(original)).position.x + 0.03, accuracy: 1e-9)
        XCTAssertEqual(editor.selection, copy)
    }

    func testDeleteRemovesAndClearsTheSelection() {
        let editor = newEditor()
        let id = editor.add(.button)
        editor.delete(id)
        XCTAssertTrue(editor.keymap.elements.isEmpty)
        XCTAssertNil(editor.selection)
        editor.delete(UUID())
        XCTAssertFalse(editor.canRedo)
    }

    func testUndoAndRedoWalkBackAndForward() throws {
        let editor = newEditor()
        let id = editor.add(.button)
        editor.update(id) { $0.label = "Reload" }
        editor.checkpoint()
        editor.move(id, to: NormalizedPoint(x: 0.2, y: 0.2))
        XCTAssertTrue(editor.canUndo)
        XCTAssertFalse(editor.canRedo)

        editor.undo()
        XCTAssertEqual(editor.element(id)?.position, NormalizedPoint(x: 0.85, y: 0.8))
        editor.undo()
        XCTAssertEqual(editor.element(id)?.label, "")
        editor.undo()
        XCTAssertTrue(editor.keymap.elements.isEmpty)
        XCTAssertNil(editor.selection, "the selected element no longer exists")
        XCTAssertFalse(editor.canUndo)

        editor.redo()
        XCTAssertEqual(editor.keymap.elements.count, 1)
        editor.redo()
        XCTAssertEqual(editor.element(id)?.label, "Reload")

        editor.undo()
        editor.add(.joystick)
        XCTAssertFalse(editor.canRedo)
    }

    func testOneDragIsOneUndoStep() {
        let editor = newEditor()
        let id = editor.add(.button)
        editor.checkpoint()
        for step in 1...30 { editor.move(id, to: NormalizedPoint(x: 0.5 + Double(step) / 100, y: 0.5)) }
        editor.undo()
        XCTAssertEqual(editor.element(id)?.position, NormalizedPoint(x: 0.85, y: 0.8), "the whole drag came back in one step")
    }

    func testTheUndoHistoryIsBounded() {
        let editor = newEditor()
        let id = editor.add(.button)
        for _ in 0..<250 { editor.update(id) { $0.label = UUID().uuidString } }
        var steps = 0
        while editor.canUndo { editor.undo(); steps += 1 }
        XCTAssertLessThanOrEqual(steps, 100)
    }

    func testEditingTheNameOrPackageMakesTheKeymapDirty() {
        let editor = newEditor()
        editor.name = "Renamed"
        XCTAssertTrue(editor.isDirty)
    }

    func testConflictsAreReportedByName() {
        let editor = newEditor()
        let a = editor.add(.button)
        let b = editor.add(.button)
        editor.update(a) { $0.label = "Reload" }
        editor.update(b) { $0.action = .button(key: 12, mode: .tap) }
        editor.update(a) { $0.action = .button(key: 12, mode: .hold) }
        XCTAssertEqual(editor.conflicts(of: b), ["Reload"])
        XCTAssertTrue(editor.isKeyUsed(12, except: b))
        XCTAssertFalse(editor.isKeyUsed(99, except: b))
        XCTAssertEqual(editor.conflicts(of: UUID()), [])
    }

    func testTitlesFallBackToTheKindOfElement() {
        let editor = newEditor()
        let id = editor.add(.button)
        XCTAssertEqual(editor.title(of: editor.element(id)!), "Button")
        editor.update(id) { $0.label = "Reload" }
        XCTAssertEqual(editor.title(of: editor.element(id)!), "Reload")
    }

    // MARK: Saving

    private func makeStore() throws -> (ProfileStore<Keymap>, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (try ProfileStore<Keymap>(kind: "keymap", root: root), root)
    }

    func testSavingANewKeymapCreatesAProfileNamedAfterThePackage() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = newEditor()
        editor.add(.button)
        editor.name = "PUBG Mobile"
        editor.package = " com.tencent.ig "

        let saved = try editor.save(into: store)
        XCTAssertEqual(saved.id, "com.tencent.ig")
        XCTAssertEqual(editor.profileID, "com.tencent.ig")
        XCTAssertFalse(editor.isDirty)
        XCTAssertEqual(try store.load(id: "com.tencent.ig").payload.package, "com.tencent.ig")
        XCTAssertEqual(try store.load(id: "com.tencent.ig").name, "PUBG Mobile")
    }

    func testSavingAgainOverwritesTheSameProfile() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = newEditor()
        editor.add(.button)
        try editor.save(into: store)
        editor.add(.joystick)
        try editor.save(into: store)
        XCTAssertEqual(store.list().count, 1)
        XCTAssertEqual(try store.load(id: try XCTUnwrap(editor.profileID)).payload.elements.count, 2)
    }

    func testANewKeymapNeverOverwritesAnotherProfileWithTheSameName() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(Profile(id: "my-keymap", name: "Other", payload: Keymap()))
        let editor = newEditor()
        XCTAssertEqual(try editor.save(into: store).id, "my-keymap-2")
        XCTAssertEqual(store.list().count, 2)
    }

    func testAnInvalidKeymapIsNotSavedAndTheProblemIsReported() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = newEditor()
        let id = editor.add(.joystick)
        editor.update(id) { $0.action = .joystick(up: 13, left: 13, down: 1, right: 2, radius: 0.1, response: 0.1) }
        XCTAssertThrowsError(try editor.save(into: store)) { XCTAssertTrue($0.localizedDescription.contains("four different keys")) }
        XCTAssertTrue(store.list().isEmpty, "nothing was written")
        XCTAssertTrue(editor.isDirty)

        editor.package = "../etc"
        editor.update(id) { $0.action = .joystick(up: 13, left: 0, down: 1, right: 2, radius: 0.1, response: 0.1) }
        XCTAssertThrowsError(try editor.save(into: store)) { XCTAssertTrue($0.localizedDescription.contains("not a valid app package")) }
    }

    func testSuggestedIdsAreSafeFileNames() {
        let editor = newEditor()
        editor.name = "Mobile Legends: Bang Bang!"
        XCTAssertEqual(editor.suggestedID(avoiding: []), "mobile-legends-bang-bang")
        editor.name = "!!!"
        XCTAssertEqual(editor.suggestedID(avoiding: []), "keymap")
        editor.name = "../../etc/passwd"
        XCTAssertEqual(editor.suggestedID(avoiding: []), "etc-passwd")
        editor.name = "Ünïcödé"
        XCTAssertTrue(ProfileFormat.isValidIdentifier(editor.suggestedID(avoiding: [])))
        editor.package = "not a package"
        XCTAssertTrue(ProfileFormat.isValidIdentifier(editor.suggestedID(avoiding: [])), "an invalid package is ignored for the id")
        XCTAssertEqual(KeymapEditorModel.slug(String(repeating: "a", count: 200)).count, 60)
    }
}

@MainActor
final class KeymapMenuChoiceTests: XCTestCase {
    func testButtonModesComeFromTheMenuKind() throws {
        let editor = KeymapEditorModel(profile: nil)
        let expected: [(KeymapEditorModel.Choice, ButtonMode)] = [(.tap, .tap), (.hold, .hold), (.toggle, .toggle)]
        for (choice, mode) in expected {
            let id = editor.addElement(choice)
            let element = try XCTUnwrap(editor.element(id))
            guard case let .button(_, actual) = element.action else { return XCTFail("\(choice) must add a button") }
            XCTAssertEqual(actual, mode)
            XCTAssertEqual(editor.selection, id, "the new element is selected")
        }
    }

    func testOtherKindsAddTheMatchingElement() throws {
        let editor = KeymapEditorModel(profile: nil)
        let kinds: [(KeymapEditorModel.Choice, (KeymapAction) -> Bool)] = [
            (.joystick, { if case .joystick = $0 { return true } else { return false } }),
            (.aim, { if case .aim = $0 { return true } else { return false } }),
            (.skillShot, { if case .skillShot = $0 { return true } else { return false } }),
        ]
        for (choice, matches) in kinds {
            let element = try XCTUnwrap(editor.element(editor.addElement(choice)))
            XCTAssertTrue(matches(element.action), "\(choice)")
        }
        XCTAssertEqual(editor.keymap.elements.count, 3)
    }
}

@MainActor
final class KeymapEditorRevertTests: XCTestCase {
    func testRevertGoesBackToWhatWasSavedAndCanBeUndone() {
        let editor = KeymapEditorModel(newFor: "com.example.game", name: "Game")
        editor.revert()
        XCTAssertTrue(editor.keymap.elements.isEmpty)
        editor.addElement(.tap)
        XCTAssertEqual(editor.keymap.elements.count, 1)
        editor.revert()
        XCTAssertTrue(editor.keymap.elements.isEmpty)
        editor.undo()
        XCTAssertEqual(editor.keymap.elements.count, 1, "Revert is one undo step")
    }

    func testNewKeymapForAGameStartsWithItsPackageAndName() {
        let editor = KeymapEditorModel(newFor: "com.mobilechess.gp", name: "Magic Chess")
        XCTAssertEqual(editor.package, "com.mobilechess.gp")
        XCTAssertEqual(editor.name, "Magic Chess")
        XCTAssertNil(editor.profileID)
    }
}
