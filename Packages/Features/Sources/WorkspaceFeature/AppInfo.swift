import Foundation

/// The user-facing product name; the project and module are named `BenzMirror`.
public enum AppInfo {
    public static let name = "Benz Mirror"
    public static let creator = "Rohman Beny Riyanto"
    public static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// The text of the About panel and the credits line.
    public static var creditLine: String { "Created by \(creator)" }
}
