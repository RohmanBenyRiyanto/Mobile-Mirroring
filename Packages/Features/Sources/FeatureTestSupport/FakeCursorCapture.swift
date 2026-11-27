import SystemServices

@MainActor
public final class FakeCursorCapture: CursorCapturing {
    public private(set) var history: [Bool] = []
    public var isCaptured: Bool { history.last ?? false }

    public init() {}

    public func setCaptured(_ captured: Bool) { history.append(captured) }
}
