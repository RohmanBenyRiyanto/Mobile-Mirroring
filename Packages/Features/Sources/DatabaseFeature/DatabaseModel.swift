import DomainModels
import Foundation
import Networking

/// What the database window needs from its host.
@MainActor
public protocol DatabaseSource: ObservableObject {
    var adb: ADB? { get }
    var targetSerial: String? { get }
    var frontPackage: String? { get }
}

@MainActor
public final class DatabaseModel: ObservableObject {
    @Published public var package = ""
    @Published public private(set) var files: [String] = []
    @Published public var selectedFile: String?
    @Published public private(set) var tables: [String] = []
    @Published public var sql = ""
    @Published public private(set) var result: [[String]] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isBusy = false
    @Published public private(set) var isTruncated = false

    private var database: AppDatabase?
    private var openFile: URL?

    public init() {}

    public var header: [String] { result.first ?? [] }
    public var rows: [[String]] { Array(result.dropFirst()) }

    public func openPackage(adb: ADB?, serial: String?) async {
        reset()
        guard let adb, let serial else { errorMessage = "No phone is connected."; return }
        let name = package.trimmingCharacters(in: .whitespaces)
        isBusy = true
        defer { isBusy = false }
        do {
            let database = try AppDatabase(adb: adb, serial: serial, package: name)
            files = try await Task.detached { try database.listFiles() }.value
            self.database = database
            if files.isEmpty { errorMessage = "This app has no databases." }
            else { await select(files.first(where: { $0.hasSuffix(".db") }) ?? files[0]) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func select(_ file: String) async {
        guard let database else { return }
        selectedFile = file
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try await Task.detached { try database.pull(file) }.value
            openFile = url
            let names = try await Task.detached { try database.query("SELECT name FROM sqlite_master WHERE type IN ('table','view') ORDER BY name", in: url) }.value
            tables = names.dropFirst().compactMap(\.first)
            errorMessage = nil
            result = []
            if let first = tables.first { await show(table: first) }
        } catch {
            tables = []
            result = []
            errorMessage = error.localizedDescription
        }
    }

    public func show(table: String) async {
        sql = "SELECT * FROM \(SQLiteQuery.quoted(table)) LIMIT 200"
        await run()
    }

    public func run() async {
        guard let database, let url = openFile else { return }
        let statement = sql
        isBusy = true
        defer { isBusy = false }
        do {
            let rows = try await Task.detached { try database.query(statement, in: url) }.value
            isTruncated = rows.count > AppDatabase.rowLimit
            result = Array(rows.prefix(AppDatabase.rowLimit))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public var csv: String { SQLiteQuery.csv(result) }

    public func reset() {
        database?.cleanUp()
        database = nil
        openFile = nil
        files = []; tables = []; result = []; selectedFile = nil; errorMessage = nil; isTruncated = false
    }
}
