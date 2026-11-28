import SwiftUI
import DomainModels
import Theme

/// The strip over the picture while editing: choose what to place, then click the screen. As in the design: Tap, Hold, Toggle, Joystick, Aim,
/// Skill Shot, Macro on the left, Revert and Done on the right.
public struct KeymapEditorToolbar: View {
    @ObservedObject public var editor: KeymapEditorModel
    public let isRecordingMacro: Bool
    public let onMacro: () -> Void
    public let onDone: () -> Void

    public init(editor: KeymapEditorModel, isRecordingMacro: Bool, onMacro: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.editor = editor
        self.isRecordingMacro = isRecordingMacro
        self.onMacro = onMacro
        self.onDone = onDone
    }

    private static let tools: [(KeymapEditorModel.Choice, LocalizedStringKey, String)] = [
        (.tap, "Tap", "hand.tap"), (.hold, "Hold", "hand.point.down"), (.toggle, "Toggle", "switch.2"),
        (.joystick, "Joystick", "gamecontroller"), (.aim, "Aim", "scope"), (.skillShot, "Skill Shot", "target"),
    ]

    public var body: some View {
        HStack(spacing: Theme.Space.s2) {
            HStack(spacing: 2) {
                ForEach(Array(Self.tools.enumerated()), id: \.offset) { _, tool in
                    Button { editor.addElement(tool.0) } label: { Label(tool.1, systemImage: tool.2).labelStyle(.titleAndIcon) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                Button(action: onMacro) { Label(isRecordingMacro ? "Stop" : "Macro", systemImage: isRecordingMacro ? "stop.circle.fill" : "list.bullet") }
                    .buttonStyle(.plain)
                    .foregroundStyle(isRecordingMacro ? Color.red : Color.primary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 4)
            .background(.ultraThinMaterial, in: Capsule())
            Spacer(minLength: Theme.Space.s2)
            Button("Revert") { editor.revert() }.buttonStyle(.plain).disabled(!editor.isDirty)
                .foregroundStyle(editor.isDirty ? Color.primary : Color.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            Button("Done", action: onDone).prominentAction()
        }
        .padding(.horizontal, Theme.Space.s3).padding(.vertical, Theme.Space.s2)
    }
}
