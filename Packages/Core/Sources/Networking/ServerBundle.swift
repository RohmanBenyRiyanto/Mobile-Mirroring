import CryptoKit
import Foundation

/// The scrcpy server that is pushed to the device and run as the `shell` user.
/// Because it runs with elevated privileges, its SHA-256 is pinned and verified
/// before every push; a swapped or corrupted file is never sent to the phone.
public enum ServerBundle {
    public static let version = "5.0.1"
    public static let fileName = "scrcpy-server-v\(version)"
    public static let sha256 = "764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536"
    public static let remotePath = "/data/local/tmp/benzmirror-server.jar"

    public enum Failure: LocalizedError {
        case missing
        case checksumMismatch(URL)

        public var errorDescription: String? {
            switch self {
            case .missing:
                return "\(ServerBundle.fileName) is missing. Run scripts/fetch-server.sh."
            case let .checksumMismatch(url):
                return "\(url.lastPathComponent) failed its SHA-256 check and was not used."
            }
        }
    }

    public static func verifiedURL() throws -> URL {
        let candidates = candidateURLs(resources: Bundle.main.resourceURL, executable: Bundle.main.executableURL,
                                       workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        guard let url = candidates.first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw Failure.missing
        }
        guard digest(of: try Data(contentsOf: url)) == sha256 else { throw Failure.checksumMismatch(url) }
        return url
    }

    /// Where the server file may be, most likely first: the app bundle; then `Resources/` in the working folder and in
    /// any folder above it or above the executable (a development build or a package test, whose working folder depends
    /// on how it was launched, for example from Xcode or from inside `Packages/Core`). Whatever is found is checked
    /// against `sha256` before use, so the location is not trusted.
    public static func candidateURLs(resources: URL?, executable: URL?, workingDirectory: URL, searchDepth: Int = 8) -> [URL] {
        var candidates = [resources?.appendingPathComponent(fileName)]
        for start in [workingDirectory, executable?.deletingLastPathComponent()] {
            var folder = start
            for _ in 0..<searchDepth {
                guard let current = folder, current.path != "/" else { break }
                candidates.append(current.appendingPathComponent("Resources/\(fileName)"))
                folder = current.deletingLastPathComponent()
            }
        }
        return candidates.compactMap { $0 }
    }

    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
