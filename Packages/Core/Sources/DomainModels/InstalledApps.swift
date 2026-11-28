import Foundation

/// An app the user can pick: its package name, a readable guess at its name, and whether it was opened recently.
public struct AppChoice: Identifiable, Equatable, Sendable {
    public let package: String
    public let name: String
    public let isRecent: Bool
    public var id: String { package }
}

/// Reads the phone's list of launchable and recent apps. Shell output only; the commands are fixed text.
public enum InstalledApps {
    public static let launchableCommand = "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER"
    public static let recentsCommand = "dumpsys activity recents | grep -E 'A=[0-9]+:'"

    public static func parse(launchableOutput: String, recentsOutput: String) -> [AppChoice] {
        var recent: [String] = []
        for line in recentsOutput.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: #"A=\d+:([A-Za-z0-9._]+)"#, options: .regularExpression) else { continue }
            let package = String(line[range]).split(separator: ":").last.map(String.init) ?? ""
            if ForegroundApp.isValidPackage(package), !recent.contains(package) { recent.append(package) }
        }
        var launchable: [String] = []
        for line in launchableOutput.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let slash = text.firstIndex(of: "/"), !text.contains(" ") else { continue }
            let package = String(text[..<slash])
            if ForegroundApp.isValidPackage(package), !launchable.contains(package) { launchable.append(package) }
        }
        let recentSet = Set(recent)
        let all = recent.filter(Set(launchable).contains) + launchable.filter { !recentSet.contains($0) }.sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
        return all.map { AppChoice(package: $0, name: displayName(for: $0), isRecent: recentSet.contains($0)) }
    }

    /// The shell cannot read the label an app shows on the home screen, so this guesses from the package name.
    public static func displayName(for package: String) -> String {
        let generic: Set<String> = ["com", "org", "net", "io", "android", "app", "apps", "mobile", "gp", "google", "sec", "samsung", "main", "client", "release", "prod"]
        let parts = package.split(separator: ".").map(String.init)
        let meaningful = parts.filter { !generic.contains($0.lowercased()) }
        let word = meaningful.last ?? parts.last ?? package
        return word.prefix(1).uppercased() + word.dropFirst()
    }

    /// Every typed word must appear in the name or the package.
    public static func filter(_ apps: [AppChoice], query: String) -> [AppChoice] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return apps }
        return apps.filter { app in
            let haystack = (app.name + " " + app.package).lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
