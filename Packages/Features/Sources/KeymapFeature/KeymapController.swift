import CoreGraphics
import Foundation
import QuartzCore
import DomainModels
import Persistence
import SystemServices

@MainActor
public final class KeymapController: ObservableObject {
    @Published public private(set) var profile: ProfileSummary?
    /// Free-look is on: the pointer is captured and mouse movement steers the camera.
    @Published public private(set) var isAiming = false
    /// While editing, the keymap is switched off so keys do not reach the phone.
    @Published public var isEditing = false {
        didSet { if isEditing { isEnabled = false } }
    }
    /// Turning this off lifts any finger still held down.
    @Published public var isEnabled = false {
        didSet { if !isEnabled { releaseAll() } }
    }

    private var engine: KeymapEngine?
    private var keymap: Keymap?
    /// Bumped whenever the engine is replaced, so a delayed lift from the old one is not applied to the new one.
    private var generation = 0
    private var frameSize = CGSize(width: 9, height: 16)
    private let send: (ControlMessage) -> Void
    private let cursor: CursorCapturing
    /// Drives joystick movement; runs only while a joystick finger is down.
    private var ticker: Timer?
    private var lastTick: CFTimeInterval = 0

    private static let tickRate = 120.0
    /// A stalled run loop must not make the stick jump: time per step is capped.
    private static let maxStep = 0.1

    public init(send: @escaping (ControlMessage) -> Void, cursor: CursorCapturing) {
        self.send = send
        self.cursor = cursor
    }

    public var hasKeymap: Bool { engine != nil }

    public func load(_ keymap: Keymap, profile: ProfileSummary?) {
        releaseAll()
        generation += 1
        engine = KeymapEngine(keymap: keymap)
        self.keymap = keymap
        self.profile = profile
    }

    public func unload() {
        releaseAll()
        generation += 1
        engine = nil
        keymap = nil
        profile = nil
        isEnabled = false
    }

    /// Lifts fingers placed for the old frame when the phone rotates.
    public func updateFrameSize(_ size: CGSize) {
        guard size != frameSize else { return }
        releaseAll()
        frameSize = size
    }

    // MARK: Keys

    public func handles(_ key: UInt16) -> Bool { isEnabled && engine?.handles(key) == true }

    public func keyDown(_ key: UInt16) -> Bool {
        guard handles(key) else { return false }
        run(engine?.keyDown(key, frameSize: frameSize) ?? [])
        updateTicker()
        syncAiming()
        return true
    }

    public func keyUp(_ key: UInt16) -> Bool {
        guard handles(key) else { return false }
        run(engine?.keyUp(key, frameSize: frameSize) ?? [])
        updateTicker()
        return true
    }

    /// A controller button or stick direction, passed on as the keyboard key the keymap bound it to. Returns true if the keymap took it.
    @discardableResult
    public func gamepad(_ input: GamepadInput, isDown: Bool) -> Bool {
        guard isEnabled, let key = keymap?.key(for: input) else { return false }
        return isDown ? keyDown(key) : keyUp(key)
    }

    public func releaseAll() {
        run(engine?.releaseAll(frameSize: frameSize) ?? [])
        updateTicker()
        syncAiming()
    }

    // MARK: Pointer (aimed skills)

    /// Aimed skills follow the pointer. The event is never consumed.
    public func pointerMoved(to ratio: CGPoint) {
        guard isEnabled else { return }
        run(engine?.pointerMoved(to: ratio, frameSize: frameSize) ?? [])
    }

    // MARK: Mouse (free-look)

    public func mouseMoved(deltaX: Double, deltaY: Double) -> Bool {
        guard isAiming else { return false }
        run(engine?.mouseMoved(deltaX: deltaX, deltaY: deltaY, frameSize: frameSize) ?? [])
        return true
    }

    /// While aiming, every click belongs to the keymap so the hidden pointer never taps the phone by accident.
    public func mouseDown(button: Int) -> Bool {
        guard isAiming else { return false }
        run(engine?.mouseDown(button: button, frameSize: frameSize) ?? [])
        return true
    }

    public func mouseUp(button: Int) -> Bool {
        guard isAiming else { return false }
        run(engine?.mouseUp(button: button, frameSize: frameSize) ?? [])
        return true
    }

    private func syncAiming() {
        let aiming = isEnabled && engine?.isAiming == true
        guard aiming != isAiming else { return }
        isAiming = aiming
        cursor.setCaptured(aiming)
    }

    // MARK: Time

    private func updateTicker() {
        guard engine?.isAnimating == true else {
            ticker?.invalidate()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1 / Self.tickRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common) // keep moving while menus are open
        ticker = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = min(now - lastTick, Self.maxStep)
        lastTick = now
        run(engine?.tick(deltaTime: elapsed, frameSize: frameSize) ?? [])
        updateTicker()
    }

    // MARK: Output

    private func run(_ actions: [KeymapEngine.Action]) {
        for action in actions {
            switch action {
            case let .send(message):
                send(message)
            case let .sendAfter(delay, message, slot):
                let expected = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    send(message) // the lift is always sent, even if the keymap changed meanwhile
                    if generation == expected { engine?.finishTap(slot: slot) }
                }
            }
        }
    }
}
