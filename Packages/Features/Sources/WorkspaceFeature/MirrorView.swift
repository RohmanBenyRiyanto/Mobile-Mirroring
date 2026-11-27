import AVFoundation
import AppKit
import SwiftUI
import DomainModels
import InspectorFeature
import KeymapFeature
import Networking

public struct MirrorView: NSViewRepresentable {
    public let session: ScrcpySession
    public let keymap: KeymapController
    public let inspector: InspectorModel
    public let design: DesignModel
    public let videoSize: CGSize
    public var onDrag: (DropSummary?) -> Void = { _ in }
    public var onDrop: ([URL]) -> Void = { _ in }
    /// Return true when the app used Esc; otherwise it is sent to the phone.
    public var onEscape: () -> Bool = { false }
    public var isStreamMode: () -> Bool = { false }
    public var onExitStreamMode: () -> Void = {}

    public init(session: ScrcpySession, keymap: KeymapController, inspector: InspectorModel, design: DesignModel, videoSize: CGSize,
                onDrag: @escaping (DropSummary?) -> Void = { _ in }, onDrop: @escaping ([URL]) -> Void = { _ in },
                onEscape: @escaping () -> Bool = { false}, isStreamMode: @escaping () -> Bool = { false },
                onExitStreamMode: @escaping () -> Void = {}) {
        self.session = session
        self.keymap = keymap
        self.inspector = inspector
        self.design = design
        self.videoSize = videoSize
        self.onDrag = onDrag
        self.onDrop = onDrop
        self.onEscape = onEscape
        self.isStreamMode = isStreamMode
        self.onExitStreamMode = onExitStreamMode
    }

    public func makeNSView(context: Context) -> MirrorNSView {
        MirrorNSView(session: session, keymap: keymap, inspector: inspector, design: design)
    }

    public func updateNSView(_ view: MirrorNSView, context: Context) {
        view.videoSize = videoSize
        view.onDrag = onDrag
        view.onDrop = onDrop
        view.onEscape = onEscape
        view.isStreamMode = isStreamMode
        view.onExitStreamMode = onExitStreamMode
    }
}

public final class MirrorNSView: NSView {
    public var videoSize = CGSize(width: 9, height: 16)
    var onDrag: (DropSummary?) -> Void = { _ in }
    var onDrop: ([URL]) -> Void = { _ in }
    var onEscape: () -> Bool = { false }
    var isStreamMode: () -> Bool = { false }
    var onExitStreamMode: () -> Void = {}
    private var swallowsRightButtonUp = false
    private let session: ScrcpySession
    private let keymap: KeymapController
    private let inspector: InspectorModel
    private let design: DesignModel
    private var focusObserver: NSObjectProtocol?
    private var isMirroredPinch = false
    private var trackpadPinch: PinchGesture?
    private var stroke = ScrollStroke()
    private var heldArrow: HeldArrow?
    private var arrowTimer: Timer?

    private struct HeldArrow {
        let keyCode: UInt16
        let direction: CGVector
        let startedAt = Date()
        var travelled = 0.0
        let scroll = ArrowScroll()
    }

    public init(session: ScrcpySession, keymap: KeymapController, inspector: InspectorModel, design: DesignModel) {
        self.session = session
        self.keymap = keymap
        self.inspector = inspector
        self.design = design
        super.init(frame: .zero)
        layer = session.decoder.layer // layer-hosting: the video is drawn straight by AVFoundation
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var isInspecting: Bool { inspector.isOn || design.capturesPointer }

    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    deinit {
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
    }

    public override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
        // A finger held by a keymap must not stay down when the window loses focus.
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [keymap] _ in
            MainActor.assumeIsolated { keymap.releaseAll() }
        }
    }

    public override func resignFirstResponder() -> Bool {
        keymap.releaseAll()
        stopArrowScroll(finishing: false)
        send(stroke.end())
        return super.resignFirstResponder()
    }

    // MARK: Files dragged onto the picture

    private func droppedFiles(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let summary = DropSummary.make(from: droppedFiles(sender)) else { return [] }
        onDrag(summary)
        return .copy
    }

    public override func draggingExited(_ sender: NSDraggingInfo?) { onDrag(nil) }

    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !droppedFiles(sender).isEmpty }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = droppedFiles(sender)
        onDrag(nil)
        guard !files.isEmpty else { return false }
        onDrop(files)
        return true
    }

    // MARK: Pointer → touch


    /// Option + drag pinches around the screen center: the second finger mirrors the pointer.
    public override func mouseDown(with event: NSEvent) {
        if isInspecting { // a tool is using the pointer: clicks do not reach the phone
            if inspector.isOn { inspector.copyHovered() } else { design.copyColor() }
            return
        }
        if keymap.mouseDown(button: 0) { return }
        isMirroredPinch = event.modifierFlags.contains(.option)
        sendTouch(.down, event)
    }

    public override func mouseDragged(with event: NSEvent) {
        reportPointer(event)
        if isInspecting { return }
        if keymap.mouseMoved(deltaX: event.deltaX, deltaY: event.deltaY) { return }
        sendTouch(.move, event)
    }

    public override func mouseUp(with event: NSEvent) {
        if isInspecting { return }
        if keymap.mouseUp(button: 0) { return }
        sendTouch(.up, event)
        isMirroredPinch = false
    }

    /// Free-look follows the mouse even when no button is held.
    public override func mouseMoved(with event: NSEvent) {
        reportPointer(event)
        _ = keymap.mouseMoved(deltaX: event.deltaX, deltaY: event.deltaY)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    public override func mouseExited(with event: NSEvent) {
        inspector.pointerMoved(to: nil)
        design.pointerMoved(to: nil)
    }

    public override func magnify(with event: NSEvent) {
        switch event.phase {
        case .began:
            guard let center = devicePosition(of: event) else { return }
            let gesture = PinchGesture(center: center)
            trackpadPinch = gesture
            sendFingers(.down, gesture.fingers)
        case .changed:
            guard var gesture = trackpadPinch else { return }
            gesture.scale(by: 1 + event.magnification)
            trackpadPinch = gesture
            sendFingers(.move, gesture.fingers)
        case .ended, .cancelled:
            guard let gesture = trackpadPinch else { return }
            sendFingers(.up, gesture.fingers)
            trackpadPinch = nil
        default:
            break
        }
    }

    /// Right click = Back, middle click = Home (same convention as scrcpy).
    public override func rightMouseDown(with event: NSEvent) {
        if isStreamMode() {
            swallowsRightButtonUp = true
            let menu = NSMenu()
            let item = menu.addItem(withTitle: String(localized: "Exit Stream Mode"), action: #selector(exitStreamMode), keyEquivalent: "")
            item.target = self
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        if keymap.mouseDown(button: 1) { return }
        session.send(.backOrScreenOn(.down))
    }

    @objc private func exitStreamMode() { onExitStreamMode() }

    public override func rightMouseUp(with event: NSEvent) {
        if swallowsRightButtonUp { swallowsRightButtonUp = false; return }
        if keymap.mouseUp(button: 1) { return }
        session.send(.backOrScreenOn(.up))
    }

    public override func rightMouseDragged(with event: NSEvent) {
        _ = keymap.mouseMoved(deltaX: event.deltaX, deltaY: event.deltaY)
    }

    public override func otherMouseDown(with event: NSEvent) {
        if keymap.mouseDown(button: event.buttonNumber) { return }
        session.send(.keycode(.down, .home))
    }

    public override func otherMouseUp(with event: NSEvent) {
        if keymap.mouseUp(button: event.buttonNumber) { return }
        session.send(.keycode(.up, .home))
    }

    public override func otherMouseDragged(with event: NSEvent) {
        _ = keymap.mouseMoved(deltaX: event.deltaX, deltaY: event.deltaY)
    }

    public override func scrollWheel(with event: NSEvent) {
        // A trackpad (or Magic Mouse) reports phases: drag a real finger so the app flings on release like under a hand.
        if event.hasPreciseScrollingDeltas, !event.phase.isEmpty || !event.momentumPhase.isEmpty {
            smoothScroll(event)
            return
        }
        guard let position = devicePosition(of: event) else { return }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 0.1 : 1
        session.send(.scroll(position,
                             horizontal: Float(event.scrollingDeltaX * scale),
                             vertical: Float(event.scrollingDeltaY * scale)))
    }

    private func smoothScroll(_ event: NSEvent) {
        // The phone does its own momentum from the release, so the Mac's inertia events are dropped.
        guard event.momentumPhase.isEmpty else { return }
        let mapper = CoordinateMapper(viewSize: bounds.size, frameSize: videoSize)
        let origin = mapper.viewPoint(forRatio: .zero), corner = mapper.viewPoint(forRatio: CGPoint(x: 1, y: 1))
        let shown = CGSize(width: max(corner.x - origin.x, 1), height: max(corner.y - origin.y, 1))

        if event.phase.contains(.began) || (event.phase.contains(.changed) && !stroke.isDown) {
            let point = convert(event.locationInWindow, from: nil)
            if let ratio = mapper.ratio(forViewPoint: CGPoint(x: point.x, y: bounds.height - point.y)) { send(stroke.begin(at: ratio)) }
        }
        if event.phase.contains(.changed) || event.phase.contains(.began) {
            send(stroke.move(by: CGVector(dx: event.scrollingDeltaX / shown.width, dy: event.scrollingDeltaY / shown.height)))
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { send(stroke.end()) }
    }

    private func send(_ outputs: [ScrollStroke.Output]) {
        let mapper = CoordinateMapper(viewSize: bounds.size, frameSize: videoSize)
        for output in outputs {
            let (action, ratio): (TouchAction, CGPoint)
            switch output {
            case let .down(point): (action, ratio) = (.down, point)
            case let .move(point): (action, ratio) = (.move, point)
            case let .up(point): (action, ratio) = (.up, point)
            }
            guard let position = mapper.touchPosition(forRatio: ratio) else { continue }
            session.send(.touch(action, position, pressure: action == .up ? 0 : 1))
        }
    }

    // MARK: Arrow keys scroll

    private static let arrowDirections: [UInt16: CGVector] = [
        126: CGVector(dx: 0, dy: 1), // up arrow: content moves down, so the finger does too
        125: CGVector(dx: 0, dy: -1),
        123: CGVector(dx: 1, dy: 0),
        124: CGVector(dx: -1, dy: 0),
    ]

    /// Plain arrow keys scroll; hold Option to send the real D-pad keys (for moving a text cursor).
    private func startArrowScroll(_ event: NSEvent) -> Bool {
        guard let direction = Self.arrowDirections[event.keyCode],
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        if event.isARepeat { return true }
        guard heldArrow == nil else { return true }
        stopArrowScroll(finishing: false)
        heldArrow = HeldArrow(keyCode: event.keyCode, direction: direction)
        send(stroke.begin(at: arrowStart(for: direction)))
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.arrowTick() } }
        RunLoop.main.add(timer, forMode: .common)
        arrowTimer = timer
        return true
    }

    private func arrowStart(for direction: CGVector) -> CGPoint {
        CGPoint(x: direction.dx == 0 ? 0.5 : (direction.dx > 0 ? 0.3 : 0.7), y: direction.dy == 0 ? 0.5 : (direction.dy > 0 ? 0.3 : 0.7))
    }

    private func arrowTick() {
        guard var held = heldArrow else { return }
        let travel = held.scroll.travel(heldFor: Date().timeIntervalSince(held.startedAt))
        let step = travel - held.travelled
        held.travelled = travel
        heldArrow = held
        let outputs = stroke.move(by: CGVector(dx: held.direction.dx * step, dy: held.direction.dy * step))
        if outputs.isEmpty, step > 0.001 { // reached the edge of the safe band: lift and take a fresh grip
            send(stroke.end())
            send(stroke.begin(at: arrowStart(for: held.direction)))
        } else {
            send(outputs)
        }
    }

    private func stopArrowScroll(finishing: Bool) {
        arrowTimer?.invalidate()
        arrowTimer = nil
        guard let held = heldArrow else { return }
        heldArrow = nil
        if finishing {
            let owed = held.scroll.remainingAtRelease(travelled: held.travelled)
            for _ in 0..<3 { send(stroke.move(by: CGVector(dx: held.direction.dx * owed / 3, dy: held.direction.dy * owed / 3))) }
        }
        send(stroke.end())
    }

    private func sendTouch(_ action: TouchAction, _ event: NSEvent) {
        guard let position = devicePosition(of: event) else { return }
        if isMirroredPinch {
            sendFingers(action, (position, PinchGesture.mirrored(position)))
        } else {
            session.send(.touch(action, position, pressure: pressure(for: action)))
        }
    }

    private func sendFingers(_ action: TouchAction, _ fingers: (first: TouchPosition, second: TouchPosition)) {
        session.send(.touch(action, fingers.first, pressure: pressure(for: action), pointer: .finger))
        session.send(.touch(action, fingers.second, pressure: pressure(for: action), pointer: .virtualFinger))
    }

    private func pressure(for action: TouchAction) -> Float { action == .up ? 0 : 1 }

    /// Tells the keymap where the pointer is on the phone's screen, for skills that are aimed with the mouse.
    private func reportPointer(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let topLeftOrigin = CGPoint(x: point.x, y: bounds.height - point.y)
        let mapper = CoordinateMapper(viewSize: bounds.size, frameSize: videoSize)
        let hovered = mapper.ratio(forViewPoint: topLeftOrigin)
        if inspector.isOn { inspector.pointerMoved(to: hovered) }
        if design.tool != .off { design.pointerMoved(to: hovered) }
        if let ratio = mapper.clampedRatio(forViewPoint: topLeftOrigin) {
            keymap.pointerMoved(to: ratio)
        }
    }

    private func devicePosition(of event: NSEvent) -> TouchPosition? {
        let point = convert(event.locationInWindow, from: nil)
        let topLeftOrigin = CGPoint(x: point.x, y: bounds.height - point.y) // AppKit's y grows upward
        return CoordinateMapper(viewSize: bounds.size, frameSize: videoSize).touchPosition(forViewPoint: topLeftOrigin)
    }

    // MARK: Keyboard

    public override func keyDown(with event: NSEvent) {
        if keymap.isEditing { return }
        if keymap.keyDown(event.keyCode) { return }
        if event.keyCode == 53, onEscape() { return }
        if startArrowScroll(event) { return }
        if let key = AndroidKeyCode(macKeyCode: event.keyCode) {
            session.send(.keycode(.down, key))
        } else if let text = typedText(from: event) {
            session.send(.text(text))
        }
    }

    public override func keyUp(with event: NSEvent) {
        if keymap.isEditing { return }
        if keymap.keyUp(event.keyCode) { return }
        if heldArrow?.keyCode == event.keyCode { stopArrowScroll(finishing: true); return }
        if let key = AndroidKeyCode(macKeyCode: event.keyCode) {
            session.send(.keycode(.up, key))
        }
    }

    /// Shift, Control and Option arrive as flag changes rather than key presses.
    public override func flagsChanged(with event: NSEvent) {
        guard let modifier = KeyNames.modifier(for: event.keyCode) else { return }
        let flag: NSEvent.ModifierFlags
        switch modifier {
        case .shift: flag = .shift
        case .control: flag = .control
        case .option: flag = .option
        }
        if event.modifierFlags.contains(flag) { _ = keymap.keyDown(event.keyCode) } else { _ = keymap.keyUp(event.keyCode) }
    }

    /// Printable characters only; Command/Control chords belong to the menu bar.
    private func typedText(from event: NSEvent) -> String? {
        guard event.modifierFlags.isDisjoint(with: [.command, .control]),
              let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) })
        else { return nil }
        return characters
    }
}
