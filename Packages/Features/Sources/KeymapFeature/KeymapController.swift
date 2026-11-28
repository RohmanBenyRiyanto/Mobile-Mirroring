import CoreGraphics
import Foundation
import QuartzCore
import DomainModels
import Persistence
import SystemServices

@MainActor
public final class KeymapController: ObservableObject {
    @Published public private(set) var profile: ProfileSummary?
    @Published public private(set) var isAiming = false
    @Published public var isEditing = false {
        didSet { if isEditing { isEnabled = false } }
    }
    @Published public var isEnabled = false {
        didSet { if !isEnabled { releaseAll() } }
    }

    private var engine: KeymapEngine?
    private var keymap: Keymap?
    private var generation = 0
    private var frameSize = CGSize(width: 9, height: 16)
    private let send: (ControlMessage) -> Void
    private let cursor: CursorCapturing
    private var ticker: Timer?
    private var lastTick: CFTimeInterval = 0

    private static let tickRate = 120.0
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
        RunLoop.main.add(timer, forMode: .common)
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
                    send(message)
                    if generation == expected { engine?.finishTap(slot: slot) }
                }
            }
        }
    }
}
