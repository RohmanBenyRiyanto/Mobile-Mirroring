import DomainModels
import Networking
import XCTest
@testable import DatabaseFeature

private final class FakeBackend: DatabaseBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var queries: [String] { lock.withLock { log } }

    func listFiles() throws -> [String] { ["app.db", "cache.db"] }
    func pull(_ name: String) throws -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(name) }
    func cleanUp() {}

    func query(_ sql: String, in file: URL) throws -> [[String]] {
        lock.withLock { log.append(sql) }
        if sql.hasPrefix("SELECT name, type FROM sqlite_master") {
            return file.lastPathComponent == "app.db" ? [["name", "type"], ["room_master_table", "table"], ["users", "table"], ["v_users", "view"]] : [["name", "type"], ["entries", "table"]]
        }
        if sql.contains("COUNT(*) AS rows") { return [["name", "rows"], ["room_master_table", "1"], ["users", "250"], ["v_users", "250"], ["entries", "3"]].filter { $0[0] != "entries" || file.lastPathComponent == "cache.db" } }
        if sql.hasPrefix("PRAGMA") { return [["cid", "name", "type"], ["0", "id", "INTEGER"], ["1", "name", "TEXT"]] }
        if sql.contains("nonsense") { throw AppDatabaseError.failed("no such table: nonsense") }
        return [["id", "name"], ["1", "Ada"], ["2", "Bo"]]
    }
}

@MainActor
final class DatabaseModelTests: XCTestCase {
    private func openedModel() async -> (DatabaseModel, FakeBackend) {
        let backend = FakeBackend()
        let model = DatabaseModel()
        model.makeBackend = { _ in backend }
        await model.open(package: "com.example.app")
        return (model, backend)
    }

    func testEveryDatabaseAndItsTablesAreListedAndTheFirstAppTableOpens() async {
        let (model, _) = await openedModel()
        XCTAssertEqual(model.databases.map(\.file), ["app.db", "cache.db"])
        XCTAssertEqual(model.databases[0].tables.map(\.name), ["room_master_table", "users", "v_users"])
        XCTAssertTrue(model.databases[0].tables[0].isSystem)
        XCTAssertEqual(model.databases[0].tables[1].rowCount, 250)
        XCTAssertEqual(model.selectedTab?.tableName, "users", "system tables are skipped when choosing what to open")
        XCTAssertEqual(model.selectedTab?.rows.count, 2)
        XCTAssertEqual(model.selectedTab?.title, "users · app.db", "with several databases the tab says which one")
        XCTAssertEqual(model.selectedTab?.knownColumns, ["id", "name"], "columns come from the structure, so an empty table still has a header")
    }

    func testSortFilterStructureAndPaging() async throws {
        let (model, backend) = await openedModel()
        let id = try XCTUnwrap(model.selectedTabID)
        await model.sort(id, by: "name")
        await model.sort(id, by: "name")
        XCTAssertEqual(model.selectedTab?.ascending, false)
        XCTAssertTrue(backend.queries.contains { $0.contains("ORDER BY \"name\" DESC") })

        await model.setFilter(TableFilter(column: "name", operation: .contains, value: "a"), for: id)
        XCTAssertTrue(backend.queries.last?.contains("WHERE \"name\" LIKE '%a%'") == true)
        XCTAssertNil(model.totalRows(of: try XCTUnwrap(model.selectedTab)), "a filtered table has no known total")
        await model.setFilter(TableFilter(column: "", operation: .equals), for: id)
        XCTAssertNil(model.selectedTab?.filter, "an incomplete filter is dropped")

        await model.setShowsStructure(true, for: id)
        XCTAssertTrue(backend.queries.last?.hasPrefix("PRAGMA table_info") == true)
        XCTAssertFalse(model.canGoForward(try XCTUnwrap(model.selectedTab)))

        await model.setShowsStructure(false, for: id)
        await model.turnPage(id, by: -1)
        XCTAssertEqual(model.selectedTab?.page, 0, "the first page is the floor")
    }

    func testQueryTabsRememberHistoryAndExplainErrors() async throws {
        let (model, _) = await openedModel()
        model.newQuery(in: "cache.db")
        let id = try XCTUnwrap(model.selectedTabID)
        XCTAssertEqual(model.selectedTab?.file, "cache.db")
        model.insert("SELECT * FROM nonsense", into: id, replacing: true)
        await model.refresh(id)
        XCTAssertTrue(model.selectedTab?.error?.contains("no such table") == true)
        XCTAssertTrue(model.selectedTab?.error?.contains("does not exist") == true, "a plain-language hint follows the error")

        model.insert("SELECT 1", into: id, replacing: true)
        await model.refresh(id)
        XCTAssertEqual(model.history.first, "SELECT 1")
        model.insert("FROM x", into: id)
        XCTAssertEqual(model.selectedTab?.sql, "SELECT 1 FROM x")
        model.close(id)
        XCTAssertNotEqual(model.selectedTabID, id)
    }

    func testNoPhoneMeansAMessageNotACrash() async {
        let model = DatabaseModel()
        await model.open(package: "com.example.app")
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.databases.isEmpty)
    }
}
