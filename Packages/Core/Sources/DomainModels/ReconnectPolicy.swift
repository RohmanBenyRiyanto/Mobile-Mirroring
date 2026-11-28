import Foundation

public enum ReconnectPolicy {
    public static let delays: [TimeInterval] = [1, 2, 4, 8, 15, 15, 15, 15]

    public static var maxAttempts: Int { delays.count }

    public static func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt <= delays.count else { return nil }
        return delays[attempt - 1]
    }
}
