import Foundation

public final class MacroRecorder: @unchecked Sendable {
    public init() {}

    private struct State {
        var isRecording = false
        var origin: TimeInterval?
        var steps: [MacroStep] = []
        var fingers: [PointerID: Int] = [:]
        var lastPosition: [Int: NormalizedPoint] = [:]
        var lastTime = 0.0
        var isFull = false
    }

    private let state = LockedValue(State())

    public var isRecording: Bool { state.get().isRecording }

    public func start() {
        state.set(State(isRecording: true))
    }

    public func observe(_ message: ControlMessage, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard case let .touch(action, position, _, pointer) = message else { return }
        state.withLock { state in
            guard state.isRecording, !state.isFull else { return }

            let finger: Int
            switch action {
            case .down:
                guard state.fingers[pointer] == nil,
                      let free = (0..<PointerID.slotCount).first(where: { !state.fingers.values.contains($0) }) else { return }
                finger = free
            case .move, .up:
                guard let known = state.fingers[pointer] else { return }
                finger = known
            }

            let origin = state.origin ?? time
            let elapsed = max(time - origin, 0)
            guard elapsed <= KeymapAction.maxMacroDuration, state.steps.count < KeymapAction.maxMacroSteps else {
                state.isFull = true
                return
            }

            let point = Self.ratio(of: position)
            if action == .move, state.lastPosition[finger] == point { return }

            state.origin = origin
            state.steps.append(MacroStep(time: elapsed, kind: Self.kind(of: action), finger: finger, position: point))
            state.lastPosition[finger] = point
            state.lastTime = elapsed
            if action == .down { state.fingers[pointer] = finger }
            if action == .up { state.fingers.removeValue(forKey: pointer) }
        }
    }

    public func stop() -> [MacroStep] {
        state.withLock { state in
            var steps = state.steps
            for finger in state.fingers.values.sorted() {
                steps.append(MacroStep(time: state.lastTime, kind: .up, finger: finger, position: state.lastPosition[finger] ?? NormalizedPoint(x: 0.5, y: 0.5)))
            }
            state = State()
            return steps
        }
    }

    // MARK: Conversions

    private static func ratio(of position: TouchPosition) -> NormalizedPoint {
        NormalizedPoint(x: position.frameWidth > 1 ? Double(position.x) / Double(position.frameWidth - 1) : 0,
                        y: position.frameHeight > 1 ? Double(position.y) / Double(position.frameHeight - 1) : 0).clamped
    }

    private static func kind(of action: TouchAction) -> MacroStep.Kind {
        switch action {
        case .down: return .down
        case .move: return .move
        case .up: return .up
        }
    }
}
