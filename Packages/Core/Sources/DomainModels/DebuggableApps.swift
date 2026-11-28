import Foundation

public enum DebuggableApps {
    public static let thirdPartyCommand = "pm list packages -3"
    public static let detailsCommand = "dumpsys package packages"

    public static func parsePackageList(_ output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("package:") else { return nil }
            let name = String(text.dropFirst("package:".count))
            return ForegroundApp.isValidPackage(name) ? name : nil
        })
    }

    public static func parse(details: String, among allowed: Set<String>? = nil) -> [String] {
        var current: String?
        var found = Set<String>()
        for rawLine in details.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Package ["), let close = line.firstIndex(of: "]") {
                current = String(line[line.index(line.startIndex, offsetBy: "Package [".count)..<close])
            } else if let name = current, line.hasPrefix("pkgFlags=[") || line.hasPrefix("flags=["), line.contains("DEBUGGABLE") {
                if allowed?.contains(name) ?? true, ForegroundApp.isValidPackage(name) { found.insert(name) }
            }
        }
        return found.sorted()
    }
}
