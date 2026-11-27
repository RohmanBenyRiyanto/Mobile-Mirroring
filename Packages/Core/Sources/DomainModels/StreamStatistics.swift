import Foundation

/// Live numbers about the incoming video, for the on-screen overlay.
public final class StreamStatistics: @unchecked Sendable {
    public struct Snapshot: Equatable {
        public var framesPerSecond = 0.0
        public var megabitsPerSecond = 0.0

        public init(framesPerSecond: Double = 0, megabitsPerSecond: Double = 0) {
            self.framesPerSecond = framesPerSecond
            self.megabitsPerSecond = megabitsPerSecond
        }
    }

    private struct Window {
        var start = Date()
        var frames = 0
        var bytes = 0
    }

    private let window = LockedValue(Window())

    public init() {}

    public func recordVideoPacket(bytes: Int, isFrame: Bool) {
        window.withLock {
            $0.bytes += bytes
            if isFrame { $0.frames += 1 }
        }
    }

    /// Rates since the previous snapshot; starts a new measurement window.
    public func snapshot(now: Date = Date()) -> Snapshot {
        window.withLock { current in
            defer { current = Window(start: now) }
            let seconds = now.timeIntervalSince(current.start)
            guard seconds > 0 else { return Snapshot() }
            return Snapshot(framesPerSecond: Double(current.frames) / seconds,
                            megabitsPerSecond: Double(current.bytes) * 8 / seconds / 1_000_000)
        }
    }
}
