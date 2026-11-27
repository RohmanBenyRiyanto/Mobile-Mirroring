import Foundation
import DomainModels
import Persistence

/// The state and rules of the keymap editor, kept apart from its views so they can be tested without a screen.
@MainActor
public final class KeymapEditorModel: ObservableObject {
    /// What the "Add" menu can create. Macros come from recording, not from here.
    public enum ElementKind: CaseIterable, Identifiable {
        case button, joystick, freeLook, mouseButton, skillShot

        public var id: Self { self }

        public var title: String {
            switch self {
            case .button: return "Button"
            case .joystick: return "Joystick (WASD)"
            case .freeLook: return "Free-look (mouse aim)"
            case .mouseButton: return "Mouse button"
            case .skillShot: return "Skill-shot"
            }
        }
    }

    @Published public private(set) var keymap: Keymap
    @Published public var name: String { didSet { if name != oldValue { isDirty = true } } }
    @Published public var package: String { didSet { if package != oldValue { isDirty = true } } }
    @Published public var selection: UUID?
    @Published public private(set) var isDirty = false
    @Published public private(set) var canUndo = false
    @Published public private(set) var canRedo = false
    /// The saved profile this edits, or nil for a keymap that has not been saved yet.
    public private(set) var profileID: String?

    private var undoStack: [Keymap] = []
    private var redoStack: [Keymap] = []
    private static let undoLimit = 100

    /// Edits `profile`, or starts a new keymap when it is nil.
    public init(profile: Profile<Keymap>?) {
        keymap = profile?.payload ?? Keymap()
        name = profile?.name ?? "My keymap"
        package = profile?.payload.package ?? ""
        profileID = profile?.id
    }

    public var selectedElement: KeymapElement? { keymap.elements.first { $0.id == selection } }

    public func element(_ id: UUID) -> KeymapElement? { keymap.elements.first { $0.id == id } }

    // MARK: Adding and removing

    /// Adds an element and selects it. A keymap has only one free-look area, so asking for another selects the one it has.
    @discardableResult
    public func add(_ kind: ElementKind) -> UUID {
        if kind == .freeLook, let existing = keymap.elements.first(where: { if case .aim = $0.action { return true } else { return false } }) {
            selection = existing.id
            return existing.id
        }
        checkpoint()
        let element = makeElement(kind)
        keymap.elements.append(element)
        selection = element.id
        return element.id
    }

    public func delete(_ id: UUID) {
        guard element(id) != nil else { return }
        checkpoint()
        keymap.elements.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    /// A copy a little to the side of the original.
    @discardableResult
    public func duplicate(_ id: UUID) -> UUID? {
        guard var copy = element(id) else { return nil }
        if case .aim = copy.action { return nil } // only one free-look area
        checkpoint()
        copy.id = UUID()
        copy.position = NormalizedPoint(x: copy.position.x + 0.03, y: copy.position.y + 0.03).clamped
        keymap.elements.append(copy)
        selection = copy.id
        return copy.id
    }

    // MARK: Changing

    /// Starts one undoable change. Call once when a drag or slider begins, then use the continuous setters.
    public func checkpoint() {
        undoStack.append(keymap)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        isDirty = true
        refreshHistory()
    }

    public func move(_ id: UUID, to point: NormalizedPoint) {
        change(id) { $0.position = point.clamped }
    }

    /// Moves the hero marker of a skill-shot.
    public func moveHero(of id: UUID, to point: NormalizedPoint) {
        change(id) { element in
            guard case let .skillShot(key, cast, radius, range, _) = element.action else { return }
            element.action = .skillShot(key: key, cast: cast, radius: radius, range: range, hero: point.clamped)
        }
    }

    /// Applies a change without adding an undo step (the caller has called `checkpoint()`).
    public func change(_ id: UUID, _ transform: (inout KeymapElement) -> Void) {
        guard let index = keymap.elements.firstIndex(where: { $0.id == id }) else { return }
        transform(&keymap.elements[index])
        isDirty = true
    }

    /// A one-off change with its own undo step (pickers, key choices, text).
    public func update(_ id: UUID, _ transform: (inout KeymapElement) -> Void) {
        guard element(id) != nil else { return }
        checkpoint()
        change(id, transform)
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(keymap)
        keymap = previous
        afterHistoryStep()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(keymap)
        keymap = next
        afterHistoryStep()
    }

    private func afterHistoryStep() {
        if let selection, element(selection) == nil { self.selection = nil }
        isDirty = true
        refreshHistory()
    }

    private func refreshHistory() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: Information

    public func title(of element: KeymapElement) -> String {
        if !element.label.isEmpty { return element.label }
        switch element.action {
        case .button: return "Button"
        case .joystick: return "Joystick"
        case .aim: return "Free-look"
        case .mouseButton: return "Mouse button"
        case .skillShot: return "Skill-shot"
        case .macro: return "Macro"
        }
    }

    /// Other elements that use any of the same keys, so the editor can warn about them.
    public func conflicts(of id: UUID) -> [String] {
        guard let element = element(id) else { return [] }
        let mine = Set(element.keys)
        return keymap.elements.filter { $0.id != id && !mine.isDisjoint(with: $0.keys) }.map(title(of:))
    }

    /// Whether a key is already used by another element.
    public func isKeyUsed(_ key: UInt16, except id: UUID) -> Bool {
        keymap.elements.contains { $0.id != id && $0.keys.contains(key) }
    }

    // MARK: Saving

    /// The keymap as it would be saved, checked and tidied; throws what is wrong with it.
    public func validatedKeymap() throws -> Keymap {
        var result = keymap
        let trimmed = package.trimmingCharacters(in: .whitespaces)
        result.package = trimmed.isEmpty ? nil : trimmed
        return try result.validated()
    }

    /// Saves into `store`: a new profile gets an id made from the package or the name; an existing one keeps its id.
    @discardableResult
    public func save(into store: ProfileStore<Keymap>) throws -> Profile<Keymap> {
        let validated = try validatedKeymap()
        let id = profileID ?? suggestedID(avoiding: Set(store.list().map(\.id)))
        let saved = try store.save(Profile(id: id, name: name, payload: validated))
        profileID = id
        name = saved.name
        keymap = validated
        isDirty = false
        return saved
    }

    /// An id for a new profile: the game's package if set, otherwise the name in lower-case letters and dashes.
    public func suggestedID(avoiding taken: Set<String>) -> String {
        let trimmedPackage = package.trimmingCharacters(in: .whitespaces)
        var base = ForegroundApp.isValidPackage(trimmedPackage) ? trimmedPackage : Self.slug(name)
        if !ProfileFormat.isValidIdentifier(base) { base = "keymap" }

        var candidate = base
        var number = 2
        while taken.contains(candidate) {
            candidate = "\(base)-\(number)"
            number += 1
        }
        return candidate
    }

    public static func slug(_ text: String) -> String {
        let mapped = text.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? String($0) : "-" }.joined()
        let collapsed = mapped.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? "keymap" : String(collapsed.prefix(60))
    }

    // MARK: New elements

    private func makeElement(_ kind: ElementKind) -> KeymapElement {
        let used = Set(keymap.elements.flatMap(\.keys))
        switch kind {
        case .button:
            return KeymapElement(label: "", position: NormalizedPoint(x: 0.85, y: 0.8), action: .button(key: Self.freeKey(avoiding: used), mode: .tap))
        case .joystick:
            return KeymapElement(label: "Move", position: NormalizedPoint(x: 0.15, y: 0.75),
                                 action: .joystick(up: 13, left: 0, down: 1, right: 2, radius: 0.12, response: 0.08))
        case .freeLook:
            return KeymapElement(label: "Look", position: NormalizedPoint(x: 0.7, y: 0.5), action: .aim(toggleKey: 50, sensitivity: 2, radius: 0.15))
        case .mouseButton:
            return KeymapElement(label: "Fire", position: NormalizedPoint(x: 0.88, y: 0.85), action: .mouseButton(button: 0, mode: .hold))
        case .skillShot:
            return KeymapElement(label: "", position: NormalizedPoint(x: 0.78, y: 0.9),
                                 action: .skillShot(key: Self.freeKey(avoiding: used), cast: .onRelease, radius: 0.12, range: 0.3,
                                                    hero: NormalizedPoint(x: 0.5, y: 0.5)))
        }
    }

    /// The first of a list of handy keys (Q, E, R, F, …) that nothing uses yet.
    public static func freeKey(avoiding used: Set<UInt16>) -> UInt16 {
        let candidates: [UInt16] = [12, 14, 15, 3, 8, 9, 7, 6, 5, 4, 17, 16, 18, 19, 20, 21]
        return candidates.first { !used.contains($0) } ?? 12
    }
}
