import CryptoKit
import Foundation

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
