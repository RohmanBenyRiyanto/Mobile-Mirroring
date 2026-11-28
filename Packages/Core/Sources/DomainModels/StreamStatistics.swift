import Foundation

public final class StreamStatistics: @unchecked Sendable {
    public struct Snapshot: Equatable {
        public var framesPerSecond = 0.0
        public var megabitsPerSecond = 0.0
        public var jitterMillis = 0.0

        public init(framesPerSecond: Double = 0, megabitsPerSecond: Double = 0, jitterMillis: Double = 0) {
            self.framesPerSecond = framesPerSecond
            self.megabitsPerSecond = megabitsPerSecond
            self.jitterMillis = jitterMillis
        }
    }

    private struct Window {
        var start = Date()
        var frames = 0
        var bytes = 0
    }

    private struct Jitter {
        var lastArrival: Date?
        var lastPresentation: Int64?
        var value = 0.0
    }

    private static let longestGapMicros: Int64 = 250_000

    private let window = LockedValue(Window())
    private let jitter = LockedValue(Jitter())

    public init() {}

    public func recordVideoPacket(bytes: Int, isFrame: Bool, presentationMicros: Int64? = nil, arrival: Date = Date()) {
        window.withLock {
            $0.bytes += bytes
            if isFrame { $0.frames += 1 }
        }
        guard isFrame, let presentationMicros else { return }
        jitter.withLock { state in
            defer { state.lastArrival = arrival; state.lastPresentation = presentationMicros }
            guard let lastArrival = state.lastArrival, let lastPresentation = state.lastPresentation else { return }
            let captured = presentationMicros - lastPresentation
            guard captured > 0, captured < Self.longestGapMicros else { return }
            let difference = abs(arrival.timeIntervalSince(lastArrival) * 1000 - Double(captured) / 1000)
            state.value += (difference - state.value) / 16
        }
    }

    public func snapshot(now: Date = Date()) -> Snapshot {
        window.withLock { current in
            defer { current = Window(start: now) }
            let seconds = now.timeIntervalSince(current.start)
            guard seconds > 0 else { return Snapshot() }
            return Snapshot(framesPerSecond: Double(current.frames) / seconds,
                            megabitsPerSecond: Double(current.bytes) * 8 / seconds / 1_000_000,
                            jitterMillis: jitter.get().value)
        }
    }
}
