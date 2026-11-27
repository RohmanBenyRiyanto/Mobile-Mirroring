import SwiftUI

public struct LogcatActions {
    public let isPaused: Bool
    public let togglePause: () -> Void
    public let clear: () -> Void
    public let focusFilter: () -> Void

    public init(isPaused: Bool, togglePause: @escaping () -> Void, clear: @escaping () -> Void, focusFilter: @escaping () -> Void) {
        self.isPaused = isPaused
        self.togglePause = togglePause
        self.clear = clear
        self.focusFilter = focusFilter
    }
}

private struct LogcatActionsKey: FocusedValueKey {
    typealias Value = LogcatActions
}

extension FocusedValues {
    /// Nil when no logcat window is in front, which disables the Logcat menu.
    public var logcatActions: LogcatActions? {
        get { self[LogcatActionsKey.self] }
        set { self[LogcatActionsKey.self] = newValue }
    }
}
