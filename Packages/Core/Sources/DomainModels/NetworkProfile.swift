import Foundation

public struct NetworkProfile: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var latencyMillis: Int
    public var downKbps: Int
    public var upKbps: Int

    public init(id: String, title: String, latencyMillis: Int, downKbps: Int, upKbps: Int) {
        self.id = id
        self.title = title
        self.latencyMillis = latencyMillis
        self.downKbps = downKbps
        self.upKbps = upKbps
    }

    public var isUnlimited: Bool { latencyMillis == 0 && downKbps == 0 && upKbps == 0 }

    public static let unlimited = NetworkProfile(id: "none", title: "No limit", latencyMillis: 0, downKbps: 0, upKbps: 0)

    public static let presets: [NetworkProfile] = [
        .unlimited,
        NetworkProfile(id: "4g", title: "4G", latencyMillis: 50, downKbps: 9_000, upKbps: 9_000),
        NetworkProfile(id: "fast3g", title: "Fast 3G", latencyMillis: 150, downKbps: 1_600, upKbps: 750),
        NetworkProfile(id: "slow3g", title: "Slow 3G", latencyMillis: 400, downKbps: 400, upKbps: 400),
        NetworkProfile(id: "edge", title: "Edge", latencyMillis: 840, downKbps: 240, upKbps: 200),
        NetworkProfile(id: "gprs", title: "GPRS", latencyMillis: 500, downKbps: 50, upKbps: 20),
    ]

    public static func preset(id: String) -> NetworkProfile { presets.first { $0.id == id } ?? .unlimited }

    public static func transferDelay(bytes: Int, kbps: Int) -> TimeInterval {
        guard kbps > 0, bytes > 0 else { return 0 }
        return min(5, Double(bytes) * 8 / (Double(kbps) * 1000))
    }
}
