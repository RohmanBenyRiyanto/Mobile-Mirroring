import SwiftUI
import DomainModels
import SystemServices

/// The editor's side panel: profile details, the list of elements, and settings for the selected one.
public struct KeymapEditorPanel: View {
    @ObservedObject public var editor: KeymapEditorModel
    @ObservedObject public var foreground: ForegroundAppDetector
    public let message: String?
    public let onSave: () -> Void
    public let onClose: (_ save: Bool) -> Void

    public init(editor: KeymapEditorModel, foreground: ForegroundAppDetector, message: String?, onSave: @escaping () -> Void, onClose: @escaping (_ save: Bool) -> Void) {
        self.editor = editor
        self.foreground = foreground
        self.message = message
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Keymap editor").font(.headline)
                    details
                    toolbar
                    elementList
                    if let element = editor.selectedElement {
                        Divider()
                        ElementInspector(editor: editor, element: element)
                    }
                }
                .padding(12)
            }
            Divider()
            footer
        }
        .frame(width: 280)
        .background(.bar)
    }

    // MARK: Parts

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: $editor.name).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Game package", text: $editor.package).textFieldStyle(.roundedBorder)
                Button("Use app in front") { if let app = foreground.current { editor.package = app.package } }
                    .disabled(foreground.current == nil)
                    .help(foreground.current.map { "Use \($0.package)" } ?? "Open the game on the phone first")
            }
            Text("With a package, this keymap can switch on by itself when that game opens.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var toolbar: some View {
        HStack {
            Menu("Add") {
                ForEach(KeymapEditorModel.ElementKind.allCases) { kind in
                    Button(kind.title) { editor.add(kind) }
                }
            }
            .fixedSize()
            Spacer()
            Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!editor.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo")
            Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!editor.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo")
        }
    }

    private var elementList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if editor.keymap.elements.isEmpty {
                Text("Nothing here yet. Use Add, then drag the new item onto the phone's screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(editor.keymap.elements) { element in
                Button { editor.selection = element.id } label: {
                    HStack {
                        Text(editor.title(of: element)).lineLimit(1)
                        Spacer()
                        Text(element.keys.map(KeyNames.name).joined(separator: " ")).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(editor.selection == element.id ? Color.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message { Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Discard") { onClose(false) }
                Spacer()
                Button("Save") { onSave() }.disabled(!editor.isDirty)
                Button("Save & Close") { onClose(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}

// MARK: - Inspector

/// Settings for the selected element; what shows depends on its kind.
private struct ElementInspector: View {
    @ObservedObject var editor: KeymapEditorModel
    let element: KeymapElement

    @FocusState private var labelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Label", text: Binding(get: { element.label }, set: { value in editor.change(element.id) { $0.label = value } }))
                .textFieldStyle(.roundedBorder)
                .focused($labelFocused)
                .onChange(of: labelFocused) { _, focused in if focused { editor.checkpoint() } }

            settings

            let conflicts = editor.conflicts(of: element.id)
            if !conflicts.isEmpty {
                Label("Shares a key with \(conflicts.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Duplicate") { editor.duplicate(element.id) }
                Button("Delete", role: .destructive) { editor.delete(element.id) }
            }
        }
    }

    @ViewBuilder
    private var settings: some View {
        switch element.action {
        case let .button(key, mode):
            KeyField(title: "Key", key: key, isUsed: editor.isKeyUsed(key, except: element.id)) { newKey in
                editor.update(element.id) { $0.action = .button(key: newKey, mode: mode) }
            }
            Picker("Behavior", selection: Binding(get: { mode }, set: { new in editor.update(element.id) { $0.action = .button(key: key, mode: new) } })) {
                Text("Tap").tag(ButtonMode.tap)
                Text("Hold").tag(ButtonMode.hold)
                Text("Toggle").tag(ButtonMode.toggle)
            }
            .pickerStyle(.segmented)

        case let .joystick(up, left, down, right, radius, response):
            joystickKeys(up: up, left: left, down: down, right: right, radius: radius, response: response)
            slider("Reach", value: radius, range: KeymapAction.radiusRange) { value in
                editor.change(element.id) { $0.action = .joystick(up: up, left: left, down: down, right: right, radius: value, response: response) }
            }
            slider("Smoothing (s)", value: response, range: 0...0.5) { value in
                editor.change(element.id) { $0.action = .joystick(up: up, left: left, down: down, right: right, radius: radius, response: value) }
            }

        case let .aim(key, sensitivity, radius):
            KeyField(title: "Toggle key", key: key, isUsed: editor.isKeyUsed(key, except: element.id)) { newKey in
                editor.update(element.id) { $0.action = .aim(toggleKey: newKey, sensitivity: sensitivity, radius: radius) }
            }
            slider("Sensitivity", value: sensitivity, range: KeymapAction.sensitivityRange) { value in
                editor.change(element.id) { $0.action = .aim(toggleKey: key, sensitivity: value, radius: radius) }
            }
            slider("Area size", value: radius, range: KeymapAction.radiusRange) { value in
                editor.change(element.id) { $0.action = .aim(toggleKey: key, sensitivity: sensitivity, radius: value) }
            }

        case let .mouseButton(button, mode):
            Picker("Button", selection: Binding(get: { button }, set: { new in editor.update(element.id) { $0.action = .mouseButton(button: new, mode: mode) } })) {
                Text("Left").tag(0)
                Text("Right").tag(1)
                Text("Middle").tag(2)
            }
            Picker("Behavior", selection: Binding(get: { mode }, set: { new in editor.update(element.id) { $0.action = .mouseButton(button: button, mode: new) } })) {
                Text("Tap").tag(ButtonMode.tap)
                Text("Hold").tag(ButtonMode.hold)
                Text("Toggle").tag(ButtonMode.toggle)
            }
            .pickerStyle(.segmented)
            Text("Works only while free-look is on.").font(.caption).foregroundStyle(.secondary)

        case let .skillShot(key, cast, radius, range, hero):
            KeyField(title: "Key", key: key, isUsed: editor.isKeyUsed(key, except: element.id)) { newKey in
                editor.update(element.id) { $0.action = .skillShot(key: newKey, cast: cast, radius: radius, range: range, hero: hero) }
            }
            Picker("Cast", selection: Binding(get: { cast }, set: { new in
                editor.update(element.id) { $0.action = .skillShot(key: key, cast: new, radius: radius, range: range, hero: hero) }
            })) {
                Text("Aim, release to cast").tag(SkillCast.onRelease)
                Text("Instant").tag(SkillCast.instant)
            }
            slider("Drag reach", value: radius, range: KeymapAction.radiusRange) { value in
                editor.change(element.id) { $0.action = .skillShot(key: key, cast: cast, radius: value, range: range, hero: hero) }
            }
            slider("Mouse range", value: range, range: KeymapAction.skillRange) { value in
                editor.change(element.id) { $0.action = .skillShot(key: key, cast: cast, radius: radius, range: value, hero: hero) }
            }
            Text("Drag the yellow marker onto your hero.").font(.caption).foregroundStyle(.secondary)

        case let .macro(key, steps, loop, speed):
            KeyField(title: "Key", key: key, isUsed: editor.isKeyUsed(key, except: element.id)) { newKey in
                editor.update(element.id) { $0.action = .macro(key: newKey, steps: steps, loop: loop, speed: speed) }
            }
            Toggle("Repeat while held", isOn: Binding(get: { loop }, set: { new in
                editor.update(element.id) { $0.action = .macro(key: key, steps: steps, loop: new, speed: speed) }
            }))
            slider("Speed", value: speed, range: KeymapAction.macroSpeedRange) { value in
                editor.change(element.id) { $0.action = .macro(key: key, steps: steps, loop: loop, speed: value) }
            }
            Text("\(steps.count) steps, \(String(format: "%.1f", steps.last?.time ?? 0)) s").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func joystickKeys(up: UInt16, left: UInt16, down: UInt16, right: UInt16, radius: Double, response: Double) -> some View {
        let apply: (UInt16, UInt16, UInt16, UInt16) -> Void = { newUp, newLeft, newDown, newRight in
            editor.update(element.id) {
                $0.action = .joystick(up: newUp, left: newLeft, down: newDown, right: newRight, radius: radius, response: response)
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            KeyField(title: "Up", key: up, isUsed: editor.isKeyUsed(up, except: element.id)) { apply($0, left, down, right) }
            KeyField(title: "Left", key: left, isUsed: editor.isKeyUsed(left, except: element.id)) { apply(up, $0, down, right) }
            KeyField(title: "Down", key: down, isUsed: editor.isKeyUsed(down, except: element.id)) { apply(up, left, $0, right) }
            KeyField(title: "Right", key: right, isUsed: editor.isKeyUsed(right, except: element.id)) { apply(up, left, down, $0) }
        }
    }

    /// A slider that is one undo step per drag, not one per pixel.
    private func slider(_ title: String, value: Double, range: ClosedRange<Double>, apply: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: apply), in: range) { began in
                if began { editor.checkpoint() }
            }
        }
    }
}

/// A button that shows a key and, when clicked, waits for the next key press to replace it.
private struct KeyField: View {
    let title: String
    let key: UInt16
    let isUsed: Bool
    let onChange: (UInt16) -> Void

    @State private var isListening = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isUsed { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary).help("Another element uses this key") }
            Button(isListening ? "Press a key…" : KeyNames.name(for: key)) { listen() }
                .frame(width: 110, alignment: .trailing)
        }
    }

    private func listen() {
        guard !isListening else { return }
        isListening = true
        Task {
            if let pressed = await KeyCapture.next() { onChange(pressed) }
            isListening = false
        }
    }
}
