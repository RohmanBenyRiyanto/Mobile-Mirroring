import CoreGraphics
import Foundation

/// Turns key presses into touches for a keymap. It is a pure state machine: the caller feeds it key events and
/// `tick`, and carries out the returned `Action`s, so it can be tested without a phone.
public struct KeymapEngine {
    public enum Action: Equatable {
        case send(ControlMessage)
        /// Send later (the lift of a tap). `releasing` is the pointer slot to hand back once it has been sent.
        case sendAfter(TimeInterval, ControlMessage, releasing: Int)
    }

    /// How long a tap keeps the finger down. Very short taps can be dropped by games.
    public static let tapDuration: TimeInterval = 0.03

    private enum Direction { case up, left, down, right }

    private struct Stick {
        let slot: Int
        var deflection = CGVector.zero // -1…1 on each axis, length at most 1
        var lastSent: TouchPosition
    }

    private struct Look {
        let slot: Int
        var offset = CGVector.zero // frame pixels from the area's centre
        var lastSent: TouchPosition
    }

    private struct Skill {
        let slot: Int
        var lastSent: TouchPosition
    }

    private struct MacroRun {
        var index = 0
        var elapsed = 0.0
        var fingers: [Int: (slot: Int, last: TouchPosition)] = [:]
        /// Fingers whose touches are skipped because no pointer slot was free when they went down.
        var dropped: Set<Int> = []
    }

    public private(set) var keymap: Keymap
    private var macros: [UUID: MacroRun] = [:]
    private var skills: [UUID: Skill] = [:]
    /// Where the mouse pointer is, as a fraction of the screen (nil until it has moved over the phone).
    private var pointer: CGPoint?
    private var elementsByKey: [UInt16: [KeymapElement]] = [:]
    private var elementsByMouseButton: [Int: [KeymapElement]] = [:]
    private var aimElement: KeymapElement?
    private var look: Look?
    private var elementsByID: [UUID: KeymapElement] = [:]
    private var pressedKeys: Set<UInt16> = []
    private var down: [UUID: Int] = [:]
    private var heldDirections: [UUID: Set<Direction>] = [:]
    private var sticks: [UUID: Stick] = [:]
    private var freeSlots = Array(0..<PointerID.slotCount)

    public init(keymap: Keymap) {
        self.keymap = keymap
        for element in keymap.elements {
            elementsByID[element.id] = element
            for key in element.keys { elementsByKey[key, default: []].append(element) }
            switch element.action {
            case .aim where aimElement == nil: aimElement = element
            case let .mouseButton(button, _): elementsByMouseButton[button, default: []].append(element)
            default: break
            }
        }
    }

    /// True while free-look is on: the mouse should be captured and its movement and buttons come here.
    public private(set) var isAiming = false

    public func handlesMouseButton(_ button: Int) -> Bool { elementsByMouseButton[button] != nil }

    /// Whether the keymap uses this key (the key event should then not reach the phone as typing).
    public func handles(_ key: UInt16) -> Bool { elementsByKey[key] != nil }

    /// True while a stick or macro is active: the caller should keep calling `tick`.
    public var isAnimating: Bool { !sticks.isEmpty || !macros.isEmpty }

    // MARK: Events

    public mutating func keyDown(_ key: UInt16, frameSize: CGSize) -> [Action] {
        guard handles(key), pressedKeys.insert(key).inserted else { return [] } // auto-repeat is ignored
        return elementsByKey[key, default: []].flatMap { press($0, key: key, frameSize: frameSize) }
    }

    public mutating func keyUp(_ key: UInt16, frameSize: CGSize) -> [Action] {
        guard pressedKeys.remove(key) != nil else { return [] }
        return elementsByKey[key, default: []].flatMap { release($0, key: key, frameSize: frameSize) }
    }

    /// Moves time forward: joysticks ease towards (or back from) their target.
    public mutating func tick(deltaTime: TimeInterval, frameSize: CGSize) -> [Action] {
        let stickActions = sticks.keys.compactMap { elementsByID[$0] }.flatMap { updateStick($0, deltaTime: deltaTime, frameSize: frameSize) }
        let macroActions = macros.keys.compactMap { elementsByID[$0] }.flatMap { advanceMacro($0, by: deltaTime, frameSize: frameSize) }
        return stickActions + macroActions
    }

    /// Lifts every finger and forgets pressed keys (focus lost, keymap switched off, screen rotated).
    public mutating func releaseAll(frameSize: CGSize) -> [Action] {
        var actions: [Action] = []
        for (id, run) in macros { actions += liftFingers(of: run, macro: id) }
        macros.removeAll()
        for (_, skill) in skills { actions.append(.send(touch(.up, skill.lastSent, skill.slot))); giveBack(skill.slot) }
        skills.removeAll()
        if let look { actions.append(.send(touch(.up, look.lastSent, look.slot))); giveBack(look.slot) }
        look = nil
        isAiming = false
        for element in keymap.elements {
            if let stick = sticks[element.id] {
                actions.append(.send(touch(.up, stick.lastSent, stick.slot)))
            } else if let slot = down[element.id], let point = position(of: element, frameSize: frameSize) {
                actions.append(.send(touch(.up, point, slot)))
            }
        }
        for slot in down.values { giveBack(slot) }
        for stick in sticks.values { giveBack(stick.slot) }
        down.removeAll()
        sticks.removeAll()
        heldDirections.removeAll()
        pressedKeys.removeAll()
        return actions
    }

    /// Hands a tap's pointer slot back once its lift has been sent.
    public mutating func finishTap(slot: Int) {
        giveBack(slot)
    }

    // MARK: Press and release

    private mutating func press(_ element: KeymapElement, key: UInt16, frameSize: CGSize) -> [Action] {
        switch element.action {
        case let .button(_, mode):
            return pressButton(element, mode: mode, frameSize: frameSize)
        case .aim:
            return toggleAim(frameSize: frameSize)
        case .mouseButton:
            return []
        case let .skillShot(_, cast, _, _, _):
            return pressSkill(element, cast: cast, frameSize: frameSize)
        case .macro, .turbo, .swipe:
            return startMacro(element, frameSize: frameSize)
        case .joystick:
            guard let direction = direction(of: key, in: element) else { return [] }
            heldDirections[element.id, default: []].insert(direction)
            return updateStick(element, deltaTime: 0, frameSize: frameSize)
        }
    }

    private mutating func release(_ element: KeymapElement, key: UInt16, frameSize: CGSize) -> [Action] {
        switch element.action {
        case let .button(_, mode):
            return releaseButton(element, mode: mode, frameSize: frameSize)
        case .aim, .mouseButton:
            return []
        case let .skillShot(_, cast, _, _, _):
            return cast == .onRelease ? releaseSkill(element) : []
        case let .macro(_, _, loop, _):
            return loop ? cancelMacro(element) : [] // a one-shot macro plays on to its end
        case .turbo:
            return cancelMacro(element) // tapping stops with the key
        case .swipe:
            return [] // a swipe plays on to its end
        case .joystick:
            guard let direction = direction(of: key, in: element) else { return [] }
            heldDirections[element.id]?.remove(direction)
            return updateStick(element, deltaTime: 0, frameSize: frameSize)
        }
    }

    // MARK: Buttons

    private mutating func pressButton(_ element: KeymapElement, mode: ButtonMode, frameSize: CGSize) -> [Action] {
        guard let point = position(of: element, frameSize: frameSize) else { return [] }

        switch mode {
        case .tap:
            guard let slot = takeSlot() else { return [] }
            return [.send(touch(.down, point, slot)), .sendAfter(Self.tapDuration, touch(.up, point, slot), releasing: slot)]
        case .hold:
            guard down[element.id] == nil, let slot = takeSlot() else { return [] }
            down[element.id] = slot
            return [.send(touch(.down, point, slot))]
        case .toggle:
            if let slot = down.removeValue(forKey: element.id) {
                giveBack(slot)
                return [.send(touch(.up, point, slot))]
            }
            guard let slot = takeSlot() else { return [] }
            down[element.id] = slot
            return [.send(touch(.down, point, slot))]
        }
    }

    private mutating func releaseButton(_ element: KeymapElement, mode: ButtonMode, frameSize: CGSize) -> [Action] {
        guard mode == .hold, let slot = down.removeValue(forKey: element.id), let point = position(of: element, frameSize: frameSize) else { return [] }
        giveBack(slot)
        return [.send(touch(.up, point, slot))]
    }

    // MARK: Joystick

    /// Brings one joystick up to date: puts its finger down when a key is held, eases the finger towards the
    /// keys' direction, and lifts it once the stick is back at the centre with no key held.
    private mutating func updateStick(_ element: KeymapElement, deltaTime: TimeInterval, frameSize: CGSize) -> [Action] {
        guard case let .joystick(_, _, _, _, radius, response) = element.action else { return [] }
        let target = targetVector(for: heldDirections[element.id] ?? [])
        var actions: [Action] = []

        if sticks[element.id] == nil {
            guard target != .zero, let center = stickPosition(of: element, deflection: .zero, radius: radius, frameSize: frameSize),
                  let slot = takeSlot() else { return [] }
            sticks[element.id] = Stick(slot: slot, lastSent: center)
            actions.append(.send(touch(.down, center, slot)))
        }
        guard var stick = sticks[element.id] else { return actions }

        stick.deflection = moved(from: stick.deflection, towards: target, over: deltaTime, response: response)
        if target == .zero, stick.deflection == .zero {
            sticks[element.id] = nil
            giveBack(stick.slot)
            let centre = stickPosition(of: element, deflection: .zero, radius: radius, frameSize: frameSize) ?? stick.lastSent
            return actions + [.send(touch(.up, centre, stick.slot))]
        }

        if let position = stickPosition(of: element, deflection: stick.deflection, radius: radius, frameSize: frameSize), position != stick.lastSent {
            stick.lastSent = position
            actions.append(.send(touch(.move, position, stick.slot)))
        }
        sticks[element.id] = stick
        return actions
    }

    /// W+D gives a diagonal of length 1, not √2, so diagonals are not faster; opposite keys cancel.
    private func targetVector(for directions: Set<Direction>) -> CGVector {
        let x = (directions.contains(.right) ? 1.0 : 0) - (directions.contains(.left) ? 1.0 : 0)
        let y = (directions.contains(.down) ? 1.0 : 0) - (directions.contains(.up) ? 1.0 : 0)
        let length = (x * x + y * y).squareRoot()
        return length == 0 ? .zero : CGVector(dx: x / length, dy: y / length)
    }

    /// Moves the stick towards `target` at a speed that crosses the full radius in `response` seconds.
    private func moved(from current: CGVector, towards target: CGVector, over deltaTime: TimeInterval, response: Double) -> CGVector {
        let step = response <= 0 ? 2.0 : deltaTime / response
        let dx = target.dx - current.dx, dy = target.dy - current.dy
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > step, distance > 0 else { return target }
        return CGVector(dx: current.dx + dx / distance * step, dy: current.dy + dy / distance * step)
    }

    private func stickPosition(of element: KeymapElement, deflection: CGVector, radius: Double, frameSize: CGSize) -> TouchPosition? {
        guard frameSize.width > 0, frameSize.height > 0 else { return nil }
        let reach = radius * Double(min(frameSize.width, frameSize.height))
        let center = element.position.clamped
        let ratio = CGPoint(x: center.x + Double(deflection.dx) * reach / Double(frameSize.width),
                            y: center.y + Double(deflection.dy) * reach / Double(frameSize.height))
        return CoordinateMapper(viewSize: frameSize, frameSize: frameSize).touchPosition(forRatio: ratio)
    }

    private func direction(of key: UInt16, in element: KeymapElement) -> Direction? {
        guard case let .joystick(up, left, down, right, _, _) = element.action else { return nil }
        switch key {
        case up: return .up
        case left: return .left
        case down: return .down
        case right: return .right
        default: return nil
        }
    }

    // MARK: Helpers

    /// The lowest free pointer slot, so ids stay small and predictable.
    private mutating func takeSlot() -> Int? { freeSlots.isEmpty ? nil : freeSlots.removeFirst() }

    private mutating func giveBack(_ slot: Int) {
        guard !freeSlots.contains(slot) else { return }
        freeSlots.append(slot)
        freeSlots.sort()
    }

    private func position(of element: KeymapElement, frameSize: CGSize) -> TouchPosition? {
        CoordinateMapper(viewSize: frameSize, frameSize: frameSize).touchPosition(forRatio: element.position.clamped.cgPoint)
    }

    private func touch(_ action: TouchAction, _ position: TouchPosition, _ slot: Int) -> ControlMessage {
        .touch(action, position, pressure: action == .up ? 0 : 1, pointer: .slot(slot))
    }
}

// MARK: - Free-look and mouse buttons

extension KeymapEngine {
    /// Mouse movement while aiming drags the look finger. Past the edge of the area the finger is lifted and put
    /// back in the middle, so the camera can keep turning in one direction.
    public mutating func mouseMoved(deltaX: Double, deltaY: Double, frameSize: CGSize) -> [Action] {
        guard isAiming, let element = aimElement, case let .aim(_, sensitivity, radius) = element.action,
              frameSize.width > 0, frameSize.height > 0,
              let centre = lookPosition(of: element, offset: .zero, frameSize: frameSize) else { return [] }

        let shorterEdge = Double(min(frameSize.width, frameSize.height))
        let scale = sensitivity * shorterEdge / 1080
        var actions: [Action] = []

        var current: Look
        if let existing = look {
            current = existing
        } else {
            guard let slot = takeSlot() else { return [] }
            current = Look(slot: slot, lastSent: centre)
            actions.append(.send(touch(.down, centre, slot)))
        }

        current.offset = CGVector(dx: current.offset.dx + deltaX * scale, dy: current.offset.dy + deltaY * scale)
        let distance = (current.offset.dx * current.offset.dx + current.offset.dy * current.offset.dy).squareRoot()
        if distance > radius * shorterEdge {
            // Put the finger back in the middle: lift where it is, touch down again at the centre.
            actions.append(.send(touch(.up, current.lastSent, current.slot)))
            actions.append(.send(touch(.down, centre, current.slot)))
            current.offset = .zero
            current.lastSent = centre
        } else if let position = lookPosition(of: element, offset: current.offset, frameSize: frameSize), position != current.lastSent {
            current.lastSent = position
            actions.append(.send(touch(.move, position, current.slot)))
        }
        look = current
        return actions
    }

    public mutating func mouseDown(button: Int, frameSize: CGSize) -> [Action] {
        guard isAiming, let elements = elementsByMouseButton[button] else { return [] }
        return elements.flatMap { element -> [Action] in
            guard case let .mouseButton(_, mode) = element.action else { return [] }
            return pressButton(element, mode: mode, frameSize: frameSize)
        }
    }

    public mutating func mouseUp(button: Int, frameSize: CGSize) -> [Action] {
        guard isAiming, let elements = elementsByMouseButton[button] else { return [] }
        return elements.flatMap { element -> [Action] in
            guard case let .mouseButton(_, mode) = element.action else { return [] }
            return releaseButton(element, mode: mode, frameSize: frameSize)
        }
    }

    /// Switches free-look on or off. Turning it off lifts the look finger and any mouse button still held.
    public mutating func toggleAim(frameSize: CGSize) -> [Action] {
        guard aimElement != nil else { return [] }
        guard isAiming else {
            isAiming = true
            return []
        }
        isAiming = false

        var actions: [Action] = []
        if let finger = look {
            actions.append(.send(touch(.up, finger.lastSent, finger.slot)))
            giveBack(finger.slot)
            look = nil
        }
        for element in keymap.elements {
            guard case .mouseButton = element.action, let slot = down.removeValue(forKey: element.id),
                  let point = position(of: element, frameSize: frameSize) else { continue }
            giveBack(slot)
            actions.append(.send(touch(.up, point, slot)))
        }
        return actions
    }

    private func lookPosition(of element: KeymapElement, offset: CGVector, frameSize: CGSize) -> TouchPosition? {
        let centre = element.position.clamped
        let ratio = CGPoint(x: centre.x + Double(offset.dx) / Double(frameSize.width),
                            y: centre.y + Double(offset.dy) / Double(frameSize.height))
        return CoordinateMapper(viewSize: frameSize, frameSize: frameSize).touchPosition(forRatio: ratio)
    }
}

// MARK: - Aimed skills

extension KeymapEngine {
    /// The mouse pointer moved over the phone (position as a fraction of the screen). Fingers of skills that are
    /// being aimed follow it.
    public mutating func pointerMoved(to ratio: CGPoint, frameSize: CGSize) -> [Action] {
        pointer = ratio
        return skills.keys.compactMap { elementsByID[$0] }.compactMap { element -> Action? in
            guard var skill = skills[element.id], let target = skillPosition(of: element, frameSize: frameSize), target != skill.lastSent else { return nil }
            skill.lastSent = target
            skills[element.id] = skill
            return .send(touch(.move, target, skill.slot))
        }
    }

    fileprivate mutating func pressSkill(_ element: KeymapElement, cast: SkillCast, frameSize: CGSize) -> [Action] {
        guard let button = position(of: element, frameSize: frameSize), skills[element.id] == nil, let slot = takeSlot() else { return [] }
        let aimed = skillPosition(of: element, frameSize: frameSize) ?? button

        var actions: [Action] = [.send(touch(.down, button, slot))]
        if aimed != button { actions.append(.send(touch(.move, aimed, slot))) }

        switch cast {
        case .onRelease:
            skills[element.id] = Skill(slot: slot, lastSent: aimed)
        case .instant:
            actions.append(.sendAfter(Self.tapDuration, touch(.up, aimed, slot), releasing: slot))
        }
        return actions
    }

    fileprivate mutating func releaseSkill(_ element: KeymapElement) -> [Action] {
        guard let skill = skills.removeValue(forKey: element.id) else { return [] }
        giveBack(skill.slot)
        return [.send(touch(.up, skill.lastSent, skill.slot))]
    }

    /// Where the finger of an aimed skill should be: the button, pushed in the direction of the mouse from the hero.
    /// Distances are measured in screen pixels, so a tall screen does not bend the direction.
    private func skillPosition(of element: KeymapElement, frameSize: CGSize) -> TouchPosition? {
        guard case let .skillShot(_, _, radius, range, hero) = element.action, let pointer, frameSize.width > 0, frameSize.height > 0 else {
            return position(of: element, frameSize: frameSize)
        }
        let width = Double(frameSize.width), height = Double(frameSize.height)
        let shorterEdge = min(width, height)
        let heroPoint = hero.clamped
        let dx = (pointer.x - heroPoint.x) * width, dy = (pointer.y - heroPoint.y) * height
        let distance = (dx * dx + dy * dy).squareRoot()

        let button = element.position.clamped
        guard distance >= Self.skillDeadZone else { return position(of: element, frameSize: frameSize) }
        let reach = radius * shorterEdge * min(distance / (range * shorterEdge), 1)
        let ratio = CGPoint(x: button.x + dx / distance * reach / width, y: button.y + dy / distance * reach / height)
        return CoordinateMapper(viewSize: frameSize, frameSize: frameSize).touchPosition(forRatio: ratio)
    }

    /// A mouse this close to the hero (in pixels) gives no direction.
    public static var skillDeadZone: Double { 2 }
}

// MARK: - Macros

extension KeymapEngine {
    /// What a macro-like element plays: its recorded steps, or steps generated for a rapid-tap button or a swipe from the element's own position.
    static func plan(for element: KeymapElement) -> (steps: [MacroStep], loop: Bool, speed: Double)? {
        let start = element.position
        switch element.action {
        case let .macro(_, steps, loop, speed):
            return (steps, loop, speed)
        case let .turbo(_, rate):
            let period = 1 / max(rate, 1)
            let hold = min(0.04, period * 0.4)
            // The last step does nothing (no finger is down then); it only makes the cycle exactly one period long.
            return ([MacroStep(time: 0, kind: .down, finger: 0, position: start), MacroStep(time: hold, kind: .up, finger: 0, position: start),
                     MacroStep(time: period, kind: .move, finger: 0, position: start)], true, 1)
        case let .swipe(_, end, duration):
            let frames = max(Int((duration * 60).rounded()), 2)
            var steps = [MacroStep(time: 0, kind: .down, finger: 0, position: start)]
            for frame in 1...frames {
                let t = Double(frame) / Double(frames)
                let point = NormalizedPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                steps.append(MacroStep(time: duration * t, kind: .move, finger: 0, position: point))
            }
            steps.append(MacroStep(time: duration + 0.016, kind: .up, finger: 0, position: end))
            return (steps, false, 1)
        default:
            return nil
        }
    }

    /// Starts playing a macro. One that is already playing is left alone.
    fileprivate mutating func startMacro(_ element: KeymapElement, frameSize: CGSize) -> [Action] {
        guard macros[element.id] == nil else { return [] }
        macros[element.id] = MacroRun()
        return advanceMacro(element, by: 0, frameSize: frameSize)
    }

    fileprivate mutating func cancelMacro(_ element: KeymapElement) -> [Action] {
        guard let run = macros.removeValue(forKey: element.id) else { return [] }
        return liftFingers(of: run, macro: element.id)
    }

    fileprivate mutating func advanceMacro(_ element: KeymapElement, by deltaTime: Double, frameSize: CGSize) -> [Action] {
        guard let plan = Self.plan(for: element), var run = macros[element.id] else { return [] }
        let (steps, loop, speed) = (plan.steps, plan.loop, plan.speed)
        let duration = steps.last?.time ?? 0
        run.elapsed += deltaTime * speed
        var actions: [Action] = []

        while true {
            while run.index < steps.count, steps[run.index].time <= run.elapsed {
                actions += play(steps[run.index], in: &run, frameSize: frameSize)
                run.index += 1
            }
            guard run.index >= steps.count else { break }
            guard loop, duration > 0 else {
                macros[element.id] = nil
                return actions + liftFingers(of: run, macro: element.id)
            }
            actions += liftFingers(of: run, macro: element.id) // a recording that ended with a finger down
            run = MacroRun(index: 0, elapsed: run.elapsed - duration)
        }
        macros[element.id] = run
        return actions
    }

    private mutating func play(_ step: MacroStep, in run: inout MacroRun, frameSize: CGSize) -> [Action] {
        guard let position = CoordinateMapper(viewSize: frameSize, frameSize: frameSize).touchPosition(forRatio: step.position.clamped.cgPoint) else { return [] }

        switch step.kind {
        case .down:
            guard run.fingers[step.finger] == nil, !run.dropped.contains(step.finger), let slot = takeSlot() else {
                run.dropped.insert(step.finger)
                return []
            }
            run.fingers[step.finger] = (slot, position)
            return [.send(touch(.down, position, slot))]
        case .move:
            guard let finger = run.fingers[step.finger], finger.last != position else { return [] }
            run.fingers[step.finger] = (finger.slot, position)
            return [.send(touch(.move, position, finger.slot))]
        case .up:
            guard let finger = run.fingers.removeValue(forKey: step.finger) else {
                run.dropped.remove(step.finger)
                return []
            }
            giveBack(finger.slot)
            return [.send(touch(.up, position, finger.slot))]
        }
    }

    private mutating func liftFingers(of run: MacroRun, macro id: UUID) -> [Action] {
        run.fingers.sorted { $0.key < $1.key }.map { _, finger in
            giveBack(finger.slot)
            return .send(touch(.up, finger.last, finger.slot))
        }
    }
}
