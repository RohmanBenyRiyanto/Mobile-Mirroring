import AVFoundation
import AppKit
import SwiftUI
import DomainModels
import InspectorFeature
import KeymapFeature
import Networking

/// Hosts the decoder's display layer and turns mouse and keyboard input into device input.
public struct MirrorView: NSViewRepresentable {
    public let session: ScrcpySession
    public let keymap: KeymapController
    public let inspector: InspectorModel
    public let design: DesignModel
    public let videoSize: CGSize

    public init(session: ScrcpySession, keymap: KeymapController, inspector: InspectorModel, design: DesignModel, videoSize: CGSize) {
        self.session = session
        self.keymap = keymap
        self.inspector = inspector
        self.design = design
        self.videoSize = videoSize
    }

    public func makeNSView(context: Context) -> MirrorNSView {
        MirrorNSView(session: session, keymap: keymap, inspector: inspector, design: design)
    }

    public func updateNSView(_ view: MirrorNSView, context: Context) {
        view.videoSize = videoSize
    }
}

public final class MirrorNSView: NSView {
    public var videoSize = CGSize(width: 9, height: 16)
    private let session: ScrcpySession
    private let keymap: KeymapController
    private let inspector: InspectorModel
    private let design: DesignModel
    private var focusObserver: NSObjectProtocol?
    private var isMirroredPinch = false
    private var trackpadPinch: PinchGesture?

    public init(session: ScrcpySession, keymap: KeymapController, inspector: InspectorModel, design: DesignModel) {
        self.session = session
        self.keymap = keymap
        self.inspector = inspector
        self.design = design
        super.init(frame: .zero)
        layer = session.decoder.layer // layer-hosting: the video is drawn straight by AVFoundation
        wantsLayer = true
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
        return super.resignFirstResponder()
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

    /// Trackpad pinch zooms around the cursor.
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
        if keymap.mouseDown(button: 1) { return }
        session.send(.backOrScreenOn(.down))
    }

    public override func rightMouseUp(with event: NSEvent) {
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
        guard let position = devicePosition(of: event) else { return }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 0.1 : 1
        session.send(.scroll(position,
                             horizontal: Float(event.scrollingDeltaX * scale),
                             vertical: Float(event.scrollingDeltaY * scale)))
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

    /// Maps the mouse position to a pixel of the (letterboxed) video frame.
    private func devicePosition(of event: NSEvent) -> TouchPosition? {
        let point = convert(event.locationInWindow, from: nil)
        let topLeftOrigin = CGPoint(x: point.x, y: bounds.height - point.y) // AppKit's y grows upward
        return CoordinateMapper(viewSize: bounds.size, frameSize: videoSize).touchPosition(forViewPoint: topLeftOrigin)
    }

    // MARK: Keyboard

    public override func keyDown(with event: NSEvent) {
        if keymap.isEditing { return }
        if keymap.keyDown(event.keyCode) { return }
        if let key = AndroidKeyCode(macKeyCode: event.keyCode) {
            session.send(.keycode(.down, key))
        } else if let text = typedText(from: event) {
            session.send(.text(text))
        }
    }

    public override func keyUp(with event: NSEvent) {
        if keymap.isEditing { return }
        if keymap.keyUp(event.keyCode) { return }
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
