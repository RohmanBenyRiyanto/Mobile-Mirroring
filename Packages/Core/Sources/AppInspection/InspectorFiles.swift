import Foundation

/// The phone's processor family, which decides which build of the daemon and agent is pushed.
public struct PhoneABI: Equatable, Sendable {
    /// Folder name in Android Studio's resources, and the value of `ro.product.cpu.abi`.
    public let folder: String
    /// The ending of the agent library's name on the phone.
    public let agentSuffix: String

    public init?(abi: String) {
        switch abi.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "arm64-v8a": self.init(folder: "arm64-v8a", agentSuffix: "arm64")
        case "armeabi-v7a": self.init(folder: "armeabi-v7a", agentSuffix: "arm")
        case "x86_64": self.init(folder: "x86_64", agentSuffix: "x86_64")
        case "x86": self.init(folder: "x86", agentSuffix: "x86")
        default: return nil
        }
    }

    private init(folder: String, agentSuffix: String) {
        self.folder = folder
        self.agentSuffix = agentSuffix
    }
}

/// Where the profiler's files live on the phone. The same folder Android Studio uses, so files it already put there are reused.
public enum PhoneInspectorPaths {
    public static let directory = "/data/local/tmp/perfd"
    public static let transport = directory + "/transport"
    public static let daemonConfig = directory + "/daemon.config"
    public static let agentConfig = directory + "/agent.config"
    public static let networkInspector = directory + "/network-inspector.jar"
    public static let perfa = directory + "/perfa.jar"
    public static func agentLibrary(for abi: PhoneABI) -> String { directory + "/libjvmtiagent_\(abi.agentSuffix).so" }
    public static let socketName = "AndroidStudioTransport"
}

/// The daemon, agent and network inspector that ship inside the user's own Android Studio. They are read from there when needed and
/// pushed to the phone; Benz Mirror does not carry Google's binaries.
public struct InspectorFiles: Equatable, Sendable {
    public let transport: URL
    public let agent: URL
    public let perfa: URL
    public let networkInspector: URL

    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var roots: [URL] = []
        for folder in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            roots += names.filter { $0.hasPrefix("Android Studio") && $0.hasSuffix(".app") }.sorted(by: >).map { folder.appendingPathComponent($0) }
        }
        return roots
    }

    /// The first Android Studio that has every file for this phone, or nil.
    public static func locate(abi: PhoneABI, roots: [URL] = defaultRoots()) -> InspectorFiles? {
        for root in roots {
            let resources = root.appendingPathComponent("Contents/plugins/android/resources")
            let files = InspectorFiles(
                transport: resources.appendingPathComponent("transport/\(abi.folder)/transport"),
                agent: resources.appendingPathComponent("transport/native/agent/\(abi.folder)/libjvmtiagent.so"),
                perfa: resources.appendingPathComponent("perfa.jar"),
                networkInspector: resources.appendingPathComponent("app-inspection/network-inspector.jar"))
            if [files.transport, files.agent, files.perfa, files.networkInspector].allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path) }) { return files }
        }
        return nil
    }
}

/// The two small settings files the daemon and agent read: where to listen, and the socket the agent connects to.
public enum InspectorConfig {
    /// daemon.config as Android Studio writes it (service address 127.0.0.1:12389, socket AndroidStudioTransport, no profiling features).
    public static let daemon = Data(hex: "0a2f0801120f3132372e302e302e313a3132333839" + "1a16416e64726f696453747564696f5472616e73706f7274" + "28014001" + "120408" + "0a1001" + "1a020801")
    /// agent.config: the same address and socket for the agent inside the app.
    public static let agent = Data(hex: "0a2f0801120f3132372e302e302e313a3132333839" + "1a16416e64726f696453747564696f5472616e73706f7274" + "28014001" + "12080832100122020801" + "18012001")
}

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            if let byte = UInt8(hex[index..<next], radix: 16) { bytes.append(byte) }
            index = next
        }
        self.init(bytes)
    }
}
