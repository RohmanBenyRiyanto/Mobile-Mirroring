import DomainModels
import Foundation

public enum AppDatabaseError: LocalizedError, Equatable {
    case notDebuggable
    case invalidName
    case notReadOnly
    case sqliteUnavailable
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notDebuggable: return "This app is not debuggable, so Android does not let any tool read its files. Only debug builds can be opened."
        case .invalidName: return "That name cannot be used."
        case .notReadOnly: return "Only read queries are allowed here."
        case .sqliteUnavailable: return "The sqlite3 tool was not found on this Mac."
        case let .failed(message): return message
        }
    }
}

/// What the database browser needs from a source of SQLite files, so it can be tested without a phone.
public protocol DatabaseBackend: AnyObject, Sendable {
    func listFiles() throws -> [String]
    func pull(_ name: String) throws -> URL
    func query(_ sql: String, in file: URL) throws -> [[String]]
    func cleanUp()
}

/// Reads a debug app's SQLite files. They are copied to a private folder on the Mac and queried there read-only; nothing is written back.
public final class AppDatabase: DatabaseBackend, @unchecked Sendable {
    private let adb: ADB
    private let serial: String
    public let package: String
    private let workFolder: URL
    private let sqlite: URL

    public static let rowLimit = 1000

    public init(adb: ADB, serial: String, package: String, sqlite: URL = URL(fileURLWithPath: "/usr/bin/sqlite3")) throws {
        guard ForegroundApp.isValidPackage(package) else { throw AppDatabaseError.invalidName }
        self.adb = adb
        self.serial = serial
        self.package = package
        self.sqlite = sqlite
        workFolder = FileManager.default.temporaryDirectory.appendingPathComponent("benzmirror-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    public func cleanUp() { try? FileManager.default.removeItem(at: workFolder) }

    deinit { cleanUp() }

    public func listFiles() throws -> [String] {
        let output: Data
        do { output = try adb.run(["-s", serial, "shell", "run-as \(package) ls databases 2>&1; true"], timeout: 10) } catch { throw Self.translate(error) }
        let text = String(decoding: output, as: UTF8.self)
        if ["not debuggable", "not an application", "Unknown package"].contains(where: text.contains) { throw AppDatabaseError.notDebuggable }
        if text.hasPrefix("run-as:") || text.contains("No such file") { return [] }
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter(SQLiteQuery.isValidFileName).sorted()
    }

    /// Copies the file (and its write-ahead log, if any) so recent changes are included.
    public func pull(_ name: String) throws -> URL {
        guard SQLiteQuery.isValidFileName(name) else { throw AppDatabaseError.invalidName }
        let target = workFolder.appendingPathComponent(name)
        for suffix in ["", "-wal", "-shm"] {
            let data: Data
            do { data = try adb.run(["-s", serial, "exec-out", "run-as \(package) cat databases/\(name)\(suffix)"], timeout: 30) } catch {
                if suffix.isEmpty { throw Self.translate(error) }
                continue
            }
            if suffix.isEmpty {
                if String(decoding: data.prefix(80), as: UTF8.self).contains("not debuggable") { throw AppDatabaseError.notDebuggable }
                guard data.starts(with: Array("SQLite format 3\u{0}".utf8)) else { throw AppDatabaseError.failed("That file is not an SQLite database.") }
            }
            if !data.isEmpty { try data.write(to: workFolder.appendingPathComponent(name + suffix), options: [.atomic]) }
        }
        return target
    }

    /// Returns the header row followed by at most `rowLimit` rows.
    public func query(_ sql: String, in file: URL) throws -> [[String]] {
        guard SQLiteQuery.isReadOnly(sql) else { throw AppDatabaseError.notReadOnly }
        guard file.deletingLastPathComponent().standardizedFileURL == workFolder.standardizedFileURL else { throw AppDatabaseError.invalidName }
        guard FileManager.default.isExecutableFile(atPath: sqlite.path) else { throw AppDatabaseError.sqliteUnavailable }

        let process = Process()
        process.executableURL = sqlite
        process.arguments = ["-readonly", "-csv", "-header", file.path, sql]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else {
            throw AppDatabaseError.failed(errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "The query did not finish." : errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Array(SQLiteQuery.parseCSV(String(decoding: data, as: UTF8.self)).prefix(Self.rowLimit + 1))
    }

    private static func translate(_ error: Error) -> Error {
        let text = error.localizedDescription
        return text.contains("not debuggable") ? AppDatabaseError.notDebuggable : error
    }
}
