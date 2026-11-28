import Foundation

public enum AppInfo {
    public static let name = "Benz Mirror"
    public static let creator = "Rohman Beny Riyanto"
    public static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let channel = (info?["BenzReleaseChannel"] as? String).map { " " + $0 } ?? ""
        return "\(short)\(channel) (\(build))"
    }

    public static var creditLine: String { "Created by \(creator)" }
}
