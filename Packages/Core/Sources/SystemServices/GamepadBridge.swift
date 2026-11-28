import DomainModels
import Foundation
import GameController

/// Listens to every connected game controller and reports its buttons and stick directions as `GamepadInput` presses.
/// It keeps working while the app is in the background, so a game can be played with the Mac window behind other windows.
@MainActor
public final class GamepadBridge {
    public private(set) var controllerNames: [String] = []
    private let onInput: (GamepadInput, Bool) -> Void
    public var onConnected: ((String) -> Void)?
    public var onDisconnected: (() -> Void)?
    private var leftStick = StickDirections.Pressed()
    private var rightStick = StickDirections.Pressed()
    private var observers: [NSObjectProtocol] = []

    public init(onInput: @escaping (GamepadInput, Bool) -> Void) {
        self.onInput = onInput
    }

    public func start() {
        GCController.shouldMonitorBackgroundEvents = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { self?.attach(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNames(); self?.onDisconnected?() }
        })
        GCController.controllers().forEach(attach)
    }

    public func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func refreshNames() { controllerNames = GCController.controllers().map { $0.vendorName ?? "Controller" } }

    private func attach(_ controller: GCController) {
        refreshNames()
        onConnected?(controller.vendorName ?? "Controller")
        guard let pad = controller.extendedGamepad else { return }
        func button(_ element: GCControllerButtonInput, _ input: GamepadInput) {
            element.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in self?.onInput(input, pressed) }
            }
        }
        button(pad.buttonA, .buttonA); button(pad.buttonB, .buttonB); button(pad.buttonX, .buttonX); button(pad.buttonY, .buttonY)
        button(pad.leftShoulder, .leftShoulder); button(pad.rightShoulder, .rightShoulder)
        button(pad.leftTrigger, .leftTrigger); button(pad.rightTrigger, .rightTrigger)
        button(pad.dpad.up, .dpadUp); button(pad.dpad.down, .dpadDown); button(pad.dpad.left, .dpadLeft); button(pad.dpad.right, .dpadRight)
        pad.leftThumbstickButton.map { button($0, .leftStickButton) }
        pad.rightThumbstickButton.map { button($0, .rightStickButton) }
        button(pad.buttonMenu, .menu)
        pad.buttonOptions.map { button($0, .options) }

        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in self?.stick(x: Double(x), y: Double(y), left: true) }
        }
        pad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor in self?.stick(x: Double(x), y: Double(y), left: false) }
        }
    }

    private func stick(x: Double, y: Double, left: Bool) {
        let previous = left ? leftStick : rightStick
        let now = StickDirections.update(x: x, y: y, previous: previous)
        if left { leftStick = now } else { rightStick = now }
        let table: [(StickDirections.Pressed, GamepadInput, GamepadInput)] = [
            (.up, .leftStickUp, .rightStickUp), (.down, .leftStickDown, .rightStickDown),
            (.left, .leftStickLeft, .rightStickLeft), (.right, .leftStickRight, .rightStickRight),
        ]
        for (direction, leftInput, rightInput) in table where previous.contains(direction) != now.contains(direction) {
            onInput(left ? leftInput : rightInput, now.contains(direction))
        }
    }
}
