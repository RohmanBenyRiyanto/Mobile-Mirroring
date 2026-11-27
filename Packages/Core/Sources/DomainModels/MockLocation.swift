import Foundation

/// A pretend position for the phone, set through the shell's test location providers (Android 12 and later).
public struct MockLocation: Equatable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Reads "-6.2, 106.8". Anything else, including out-of-range numbers, is refused.
    public init?(text: String) {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        self.init(latitude: lat, longitude: lon)
    }

    public static let presets: [(name: String, location: MockLocation)] = [
        ("Jakarta", MockLocation(latitude: -6.2088, longitude: 106.8456)!),
        ("Singapore", MockLocation(latitude: 1.3521, longitude: 103.8198)!),
        ("Tokyo", MockLocation(latitude: 35.6762, longitude: 139.6503)!),
        ("London", MockLocation(latitude: 51.5072, longitude: -0.1276)!),
        ("New York", MockLocation(latitude: 40.7128, longitude: -74.0060)!),
    ]

    public var text: String { String(format: "%.6f, %.6f", latitude, longitude) }

    static let providers = ["gps", "network"]

    /// Allows the shell to mock, then creates and fills the providers. Safe to repeat.
    public var startCommand: String {
        (["appops set --uid 2000 android:mock_location allow"]
            + Self.providers.map { "cmd location providers add-test-provider \($0) --supportsAltitude --supportsSpeed --supportsBearing" }
            + Self.providers.map { "cmd location providers set-test-provider-enabled \($0) true" }
            + [updateCommand]).joined(separator: "; ")
    }

    /// Sends the position again; the system forgets a test fix after a while, so this is repeated while mocking.
    public var updateCommand: String {
        Self.providers.map {
            String(format: "cmd location providers set-test-provider-location \($0) --location %.6f,%.6f --accuracy 5", latitude, longitude)
        }.joined(separator: "; ")
    }

    public static let stopCommand: String =
        (providers.map { "cmd location providers remove-test-provider \($0)" } + ["appops set --uid 2000 android:mock_location default"]).joined(separator: "; ")
}
