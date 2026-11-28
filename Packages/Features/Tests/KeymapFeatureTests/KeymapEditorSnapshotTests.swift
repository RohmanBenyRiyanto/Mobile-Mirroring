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
}
