import Foundation

/// When to try again after the connection to a phone dropped: quickly at first, then less often, and finally give up.
public enum ReconnectPolicy {
    public static let delays: [TimeInterval] = [1, 2, 4, 8, 15, 15, 15, 15]

    public static var maxAttempts: Int { delays.count }

    /// Seconds to wait before attempt number `attempt` (1-based), or nil when it is time to stop.
    public static func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt <= delays.count else { return nil }
        return delays[attempt - 1]
    }
}
