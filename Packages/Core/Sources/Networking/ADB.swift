import DomainModels
import Foundation

public struct AndroidDevice: Identifiable, Hashable {
    public enum State: String { case device, unauthorized, offline, other }

    public let serial: String
    public let state: State
    public let model: String?
    /// The device code name from `adb devices -l` (such as "dm1q"), a fallback when the model is not in the name list.
    public let codename: String?

    public init(serial: String, state: State, model: String?, codename: String? = nil) {
        self.serial = serial
        self.state = state
        self.model = model
        self.codename = codename
    }

    public var id: String { serial }
    public var isReady: Bool { state == .device }
    public var title: String {
        DeviceNameDirectory.bundled.name(model: model, codename: codename) ?? model?.replacingOccurrences(of: "_", with: " ") ?? serial
    }

    /// Serials end up as arguments to `adb -s`, so accept only the characters adb itself emits.
    public static func isValidSerial(_ serial: String) -> Bool {
        !serial.isEmpty && serial.count <= 128
            && serial.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._:-".contains($0)) }
    }
}

public enum ADBError: LocalizedError {
    case notFound
    case failed(command: String, message: String)
    case timedOut(command: String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "adb not found. Install Android platform-tools (brew install android-platform-tools)."
        case let .failed(command, message):
            if let friendly = FriendlyErrors.explain(message) { return String(localized: String.LocalizationValue(friendly)) }
            return "adb \(command) failed: \(message)"
        case let .timedOut(command):
            return "adb \(command) timed out"
        }
    }
}

/// Thin wrapper around the `adb` executable. Commands are always passed as an argument
/// array to `Process`; no shell is ever involved.
public struct ADB: Sendable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// An adb the user chose, if it is an executable file that answers `version`.
    public static func custom(path: String) -> ADB? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let adb = ADB(executable: URL(fileURLWithPath: path))
        guard let out = try? adb.run(["version"], timeout: 5), String(decoding: out, as: UTF8.self).contains("Android Debug Bridge") else { return nil }
        return adb
    }

    /// The chosen adb when there is one that works, otherwise the first adb found in the usual places.
    public static func locate(preferring path: String?) -> ADB? {
        if let path, !path.isEmpty, let chosen = custom(path: path) { return chosen }
        return locate()
    }

    public static func locate() -> ADB? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(home)/Library/Android/sdk/platform-tools/adb",
        ]
        for variable in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = ProcessInfo.processInfo.environment[variable] {
                candidates.append("\(root)/platform-tools/adb")
            }
        }
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { ADB(executable: URL(fileURLWithPath: $0)) }
    }

    // MARK: Running commands

    /// Runs adb to completion and returns its raw stdout.
    @discardableResult
    public func run(_ arguments: [String], input: Data? = nil, timeout: TimeInterval = 30) throws -> Data {
        let process = makeProcess(arguments)
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdin = Pipe()
        if input != nil { process.standardInput = stdin }

        let outputDrain = PipeDrain(stdout)
        let errorDrain = PipeDrain(stderr)
        try process.run()
        if let input { // secrets such as pairing codes go through stdin, never the visible argument list
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }

        let timedOut = Flag()
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        let output = outputDrain.wait()
        let errorOutput = errorDrain.wait()
        process.waitUntilExit()
        watchdog.cancel()

        let command = arguments.first(where: { !$0.hasPrefix("-") }) ?? "command"
        if timedOut.isSet { throw ADBError.timedOut(command: command) }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ADBError.failed(command: command, message: message.isEmpty ? "exit \(process.terminationStatus)" : message)
        }
        return output
    }

    /// Creates a not-yet-started process, for long-running commands such as the server.
    public func makeProcess(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        return process
    }

    // MARK: Queries

    public func devices() throws -> [AndroidDevice] {
        let output = String(decoding: try run(["devices", "-l"], timeout: 10), as: UTF8.self)
        return output.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, AndroidDevice.isValidSerial(fields[0]) else { return nil }
            let model = fields.first { $0.hasPrefix("model:") }.map { String($0.dropFirst("model:".count)) }
            let codename = fields.first { $0.hasPrefix("device:") }.map { String($0.dropFirst("device:".count)) }
            return AndroidDevice(serial: fields[0], state: AndroidDevice.State(rawValue: fields[1]) ?? .other, model: model, codename: codename)
        }
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

/// Reads a pipe to EOF on a background queue so a full pipe can never stall the child.
private final class PipeDrain: @unchecked Sendable {
    private var data = Data()
    private let group = DispatchGroup()

    init(_ pipe: Pipe) {
        group.enter()
        DispatchQueue.global().async {
            self.data = pipe.fileHandleForReading.readDataToEndOfFile()
            self.group.leave()
        }
    }

    func wait() -> Data {
        group.wait()
        return data
    }
}
