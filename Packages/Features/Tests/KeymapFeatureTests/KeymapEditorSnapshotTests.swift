import AppKit
import SwiftUI
import XCTest
import TestSupport
@testable import DomainModels
@testable import KeymapFeature
@testable import Persistence

@MainActor
final class KeymapEditorSnapshotTests: XCTestCase {
    private func exampleEditor() throws -> KeymapEditorModel {
        let file = projectFile("Resources/Examples/example.benzkeymap")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = try ProfileStore<Keymap>(kind: "keymap", root: root).importData(try Data(contentsOf: file))
        return KeymapEditorModel(profile: profile)
    }

    private var fakePhone: some View {
        LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
    }

    private func editorScene(_ editor: KeymapEditorModel, message: String? = nil) -> some View {
        HStack(spacing: 0) {
            ZStack {
                fakePhone
                KeymapEditorOverlay(editor: editor, videoSize: CGSize(width: 1080, height: 2340))
            }
            .frame(width: 400, height: 867)
            KeymapEditorPanel(editor: editor, foreground: ForegroundAppDetector(), message: message, onSave: {}, onClose: { _ in })
        }
    }

    func testTheEditorRendersWithEveryKindOfElement() throws {
        let editor = try exampleEditor()
        editor.selection = editor.keymap.elements.first { if case .skillShot = $0.action { return true } else { return false } }?.id

        let image = try renderSnapshot(editorScene(editor), size: CGSize(width: 680, height: 867), name: "editor-skillshot")
        XCTAssertGreaterThan(image.pixelsWide, 600)
        XCTAssertFalse(isBlankImage(image), "the editor drew nothing")
    }

    func testEachInspectorRenders() throws {
        let editor = try exampleEditor()
        for element in editor.keymap.elements {
            editor.selection = element.id
            let image = try renderSnapshot(editorScene(editor), size: CGSize(width: 680, height: 867), name: "inspector-\(editor.title(of: element).filter { $0.isLetter || $0.isNumber })")
            XCTAssertFalse(isBlankImage(image), editor.title(of: element))
        }
    }

    func testAnEmptyKeymapAndAnErrorMessageRender() throws {
        let editor = KeymapEditorModel(profile: nil)
        let image = try renderSnapshot(editorScene(editor, message: "A joystick needs four different keys and valid numbers."),
                               size: CGSize(width: 680, height: 867), name: "editor-empty")
        XCTAssertFalse(isBlankImage(image))
    }

    func testTheEditorRendersInDarkAppearance() throws {
        let editor = try exampleEditor()
        editor.selection = editor.keymap.elements.first?.id
        let image = try renderSnapshot(editorScene(editor), size: CGSize(width: 680, height: 867), name: "editor-dark", appearance: .darkAqua)
        XCTAssertFalse(isBlankImage(image))
    }

    /// A landscape game: the picture on the left with the toolbar over it and the profiles panel on the right, as in the app.
    func testTheEditorRendersForALandscapeGame() throws {
        let editor = try exampleEditor()
        editor.selection = editor.keymap.elements.first?.id
        let scene = HStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.07, green: 0.16, blue: 0.40), Color(red: 0.02, green: 0.05, blue: 0.16)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 1, green: 0.93, blue: 0.7).opacity(0.85)).frame(width: 90, height: 90).offset(x: 220, y: -120)
                Ellipse().fill(Color(red: 0.05, green: 0.2, blue: 0.5)).frame(width: 900, height: 260).offset(x: -150, y: 230)
                KeymapEditorOverlay(editor: editor, videoSize: CGSize(width: 2340, height: 1080))
            }
            .frame(width: 1040, height: 480)
            .overlay(alignment: .top) { KeymapEditorToolbar(editor: editor, isRecordingMacro: false, onMacro: {}, onDone: {}) }
            KeymapEditorPanel(editor: editor, foreground: ForegroundAppDetector(), message: nil,
                              profiles: [ProfileSummary(id: "a", name: "Magic Chess", modified: Date()), ProfileSummary(id: "b", name: "Skyline Arena", modified: Date())],
                              onSave: {}, onClose: { _ in })
        }
        let image = try renderSnapshot(scene.tint(Color(red: 0.04, green: 0.52, blue: 1)), size: CGSize(width: 1320, height: 480), name: "editor-landscape", appearance: .darkAqua)
        XCTAssertFalse(isBlankImage(image))
    }
}
