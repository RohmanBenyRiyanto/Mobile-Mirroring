import Components
import CryptoKit
import DomainModels
import Foundation
import Networking

/// What the database window needs from its host.
@MainActor
public protocol DatabaseSource: ObservableObject {
    var adb: ADB? { get }
    var targetSerial: String? { get }
    var frontPackage: String? { get }
    var appPickerItems: [PickerItem] { get }
    var isLoadingApps: Bool { get }
    func loadInstalledApps() async
    func makeDatabaseBackend(package: String) throws -> DatabaseBackend
}

public struct TableInfo: Identifiable, Equatable, Sendable {
    public let name: String
    public let isView: Bool
    public var rowCount: Int?
    public var id: String { name }
    public var isSystem: Bool { SQLiteQuery.isSystemTable(name) }
}

/// One database file of the app (an app can have several, as Room apps often do) with its tables once they are read.
public struct DatabaseEntry: Identifiable, Equatable {
    public let file: String
    public var tables: [TableInfo] = []
    public var isLoaded = false
    public var error: String?
    public var id: String { file }
}

/// One open tab, as in Android Studio's Database Inspector: a table (browsable, filterable, sortable, paged) or a query.
public struct InspectorTab: Identifiable, Equatable {
    public enum Kind: Equatable { case table(file: String, name: String), query(file: String) }

    public let id = UUID()
    public var kind: Kind
    public var title: String
    public var sql = ""
    public var result: [[String]] = []
    public var page = 0
    public var sortColumn: String?
    public var ascending = true
    public var filter: TableFilter?
    public var showsStructure = false
    /// Column names from the table's structure, so an empty table still shows its columns (a query with no rows prints no header).
    public var knownColumns: [String] = []
    public var error: String?
    public var isTruncated = false

    public var file: String { switch kind { case let .table(file, _), let .query(file): return file } }
    public var header: [String] { showsStructure ? (result.first ?? []) : (result.first ?? knownColumns) }
    public var rows: [[String]] { result.first == nil ? [] : Array(result.dropFirst()) }
    public var tableName: String? { if case let .table(_, name) = kind { return name } else { return nil } }
    public var isQuery: Bool { if case .query = kind { return true } else { return false } }
}

@MainActor
public final class DatabaseModel: ObservableObject {
    @Published public var package = ""
    @Published public private(set) var databases: [DatabaseEntry] = []
    @Published public private(set) var tabs: [InspectorTab] = []
    @Published public var selectedTabID: UUID?
    @Published public private(set) var history: [String] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isBusy = false
    @Published public private(set) var isLive = false

    public var makeBackend: @Sendable (String) throws -> DatabaseBackend = { _ in throw AppDatabaseError.invalidName }
    private var backend: DatabaseBackend?
    private var urls: [String: URL] = [:]
    private var digests: [String: SHA256.Digest] = [:]
    private var liveTask: Task<Void, Never>?
    private static let historyLimit = 20
    private static let maxFiles = 16

    public init() {}

    public var selectedTab: InspectorTab? { tabs.first { $0.id == selectedTabID } }

    // MARK: Opening

    /// Lists the app's database files and reads the schema of each, so every database and table is in the sidebar at once.
    public func open(package name: String) async {
        reset()
        package = name
        isBusy = true
        defer { isBusy = false }
        do {
            let backend = try makeBackend(name)
            let files = try await Task.detached { try backend.listFiles() }.value
            self.backend = backend
            guard !files.isEmpty else { errorMessage = "This app has no databases."; return }
            databases = files.prefix(Self.maxFiles).map { DatabaseEntry(file: $0) }
            for entry in databases { await load(entry.file) }
            if let first = databases.first(where: { !$0.tables.filter { !$0.isSystem }.isEmpty }), let table = first.tables.first(where: { !$0.isSystem }) {
                await openTable(table.name, in: first.file)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(_ file: String) async {
        guard let backend else { return }
        do {
            let url = try await Task.detached { try backend.pull(file) }.value
            urls[file] = url
            digests[file] = Self.digest(of: url)
            let tables = try await schema(of: url)
            update(entry: file) { $0.tables = tables; $0.isLoaded = true; $0.error = nil }
        } catch {
            update(entry: file) { $0.isLoaded = true; $0.error = error.localizedDescription }
        }
    }

    private func schema(of url: URL) async throws -> [TableInfo] {
        guard let backend else { return [] }
        let rows = try await Task.detached { try backend.query(SQLiteQuery.schemaSQL, in: url) }.value.dropFirst()
        var found = rows.compactMap { $0.count >= 2 ? TableInfo(name: $0[0], isView: $0[1] == "view", rowCount: nil) : nil }
        if let sql = SQLiteQuery.countsSQL(tables: found.map(\.name)), let counts = try? await Task.detached(operation: { try backend.query(sql, in: url) }).value.dropFirst() {
            let byName = Dictionary(counts.compactMap { $0.count >= 2 ? ($0[0], Int($0[1])) : nil }, uniquingKeysWith: { first, _ in first })
            for index in found.indices { found[index].rowCount = byName[found[index].name] ?? nil }
        }
        return found
    }

    // MARK: Tabs

    public func openTable(_ name: String, in file: String) async {
        if let existing = tabs.first(where: { $0.kind == .table(file: file, name: name) }) { selectedTabID = existing.id; return await refresh(existing.id) }
        // With several databases the tab also names its file, shortened; the full name is in the sidebar.
        let short = file.count > 14 ? String(file.prefix(13)) + "…" : file
        let title = databases.count > 1 ? "\(name) · \(short)" : name
        let tab = InspectorTab(kind: .table(file: file, name: name), title: title)
        tabs.append(tab)
        selectedTabID = tab.id
        await refresh(tab.id)
    }

    public func newQuery(in file: String? = nil) {
        guard let target = file ?? selectedTab?.file ?? databases.first?.file else { return }
        var tab = InspectorTab(kind: .query(file: target), title: String(localized: "New query"))
        if let table = selectedTab?.tableName { tab.sql = "SELECT * FROM \(SQLiteQuery.quoted(table)) LIMIT 100" }
        tabs.append(tab)
        selectedTabID = tab.id
    }

    public func close(_ id: UUID) {
        tabs.removeAll { $0.id == id }
        if selectedTabID == id { selectedTabID = tabs.last?.id }
    }

    public func setSQL(_ sql: String, for id: UUID) { update(id) { $0.sql = sql } }

    /// Adds text to the query being written: a table or column name, or a ready-made template.
    public func insert(_ text: String, into id: UUID, replacing: Bool = false) {
        update(id) { tab in
            if replacing || tab.sql.isEmpty { tab.sql = text } else { tab.sql += (tab.sql.hasSuffix(" ") || tab.sql.hasSuffix("\n") ? "" : " ") + text }
        }
    }

    /// Points a query tab at another database of the same app.
    public func moveQuery(_ id: UUID, to file: String) { update(id) { if $0.isQuery { $0.kind = .query(file: file) } } }

    public func columns(of tab: InspectorTab) -> [String] { tab.isQuery ? [] : tab.header }

    public func tables(in file: String) -> [TableInfo] { databases.first { $0.file == file }?.tables ?? [] }

    // MARK: Running

    /// Runs what the tab shows: the generated page (or structure) for a table, or the typed text for a query.
    public func refresh(_ id: UUID) async {
        guard let backend, let tab = tabs.first(where: { $0.id == id }), let url = urls[tab.file] else { return }
        var sql = tab.sql
        if let table = tab.tableName {
            sql = tab.showsStructure ? SQLiteQuery.structureSQL(table: table)
                : SQLiteQuery.pageSQL(table: table, filter: tab.filter, sortColumn: tab.sortColumn, ascending: tab.ascending, page: tab.page)
            update(id) { $0.sql = sql }
        }
        isBusy = true
        defer { isBusy = false }
        do {
            if let table = tab.tableName, tab.knownColumns.isEmpty,
               let structure = try? await Task.detached(operation: { try backend.query(SQLiteQuery.structureSQL(table: table), in: url) }).value {
                update(id) { $0.knownColumns = structure.dropFirst().compactMap { $0.count > 1 ? $0[1] : nil } }
            }
            let rows = try await Task.detached { try backend.query(sql, in: url) }.value
            update(id) { $0.result = Array(rows.prefix(AppDatabase.rowLimit + 1)); $0.error = nil; $0.isTruncated = rows.count > AppDatabase.rowLimit + 1 }
            if tab.isQuery { remember(sql) }
        } catch {
            let hint = SQLiteQuery.hint(forError: error.localizedDescription).map { "\n" + String(localized: String.LocalizationValue($0)) } ?? ""
            update(id) { $0.error = error.localizedDescription + hint }
        }
    }

    public func sort(_ id: UUID, by column: String) async {
        update(id) { tab in
            if tab.sortColumn == column { tab.ascending.toggle() } else { tab.sortColumn = column; tab.ascending = true }
            tab.page = 0
        }
        await refresh(id)
    }

    public func turnPage(_ id: UUID, by delta: Int) async {
        update(id) { $0.page = max($0.page + delta, 0) }
        await refresh(id)
    }

    public func setFilter(_ filter: TableFilter?, for id: UUID) async {
        update(id) { $0.filter = (filter?.isComplete == true) ? filter : nil; $0.page = 0 }
        await refresh(id)
    }

    public func setShowsStructure(_ on: Bool, for id: UUID) async {
        update(id) { $0.showsStructure = on }
        await refresh(id)
    }

    public func canGoForward(_ tab: InspectorTab) -> Bool { !tab.showsStructure && tab.rows.count >= SQLiteQuery.pageSize }

    public func totalRows(of tab: InspectorTab) -> Int? {
        guard tab.filter == nil, let name = tab.tableName else { return nil }
        return tables(in: tab.file).first { $0.name == name }?.rowCount
    }

    private func remember(_ sql: String) {
        history.removeAll { $0 == sql }
        history.insert(sql, at: 0)
        if history.count > Self.historyLimit { history.removeLast() }
    }

    private func update(_ id: UUID, _ change: (inout InspectorTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        change(&tabs[index])
    }

    private func update(entry file: String, _ change: (inout DatabaseEntry) -> Void) {
        guard let index = databases.firstIndex(where: { $0.file == file }) else { return }
        change(&databases[index])
    }

    // MARK: Live updates

    /// While on, every file is copied again every two seconds and what changed is refreshed.
    public func setLive(_ on: Bool) {
        isLive = on
        liveTask?.cancel()
        liveTask = nil
        guard on else { return }
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.pollForChanges()
            }
        }
    }

    private func pollForChanges() async {
        guard let backend, !isBusy else { return }
        for entry in databases {
            guard let url = try? await Task.detached(operation: { try backend.pull(entry.file) }).value else { continue }
            let digest = Self.digest(of: url)
            guard digest != digests[entry.file] else { continue }
            digests[entry.file] = digest
            urls[entry.file] = url
            if let tables = try? await schema(of: url) { update(entry: entry.file) { $0.tables = tables } }
            for tab in tabs where tab.file == entry.file && (!tab.isQuery || !tab.sql.isEmpty) { await refresh(tab.id) }
        }
    }

    private static func digest(of url: URL) -> SHA256.Digest? {
        (try? Data(contentsOf: url, options: .mappedIfSafe)).map { SHA256.hash(data: $0) }
    }

    // MARK: Export and cleanup

    public func csv(for tab: InspectorTab) -> String { SQLiteQuery.csv(tab.result) }

    public func reset() {
        liveTask?.cancel()
        liveTask = nil
        isLive = false
        backend?.cleanUp()
        backend = nil
        urls = [:]
        digests = [:]
        databases = []; tabs = []; selectedTabID = nil; errorMessage = nil
    }
}
