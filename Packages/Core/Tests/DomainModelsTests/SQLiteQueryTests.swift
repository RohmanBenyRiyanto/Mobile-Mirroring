import XCTest
@testable import DomainModels

final class SQLiteQueryTests: XCTestCase {
    func testOnlyPlainReadsPass() {
        XCTAssertTrue(SQLiteQuery.isReadOnly("SELECT * FROM users LIMIT 5;"))
        XCTAssertTrue(SQLiteQuery.isReadOnly("  with a as (select 1) select * from a"))
        XCTAssertTrue(SQLiteQuery.isReadOnly("PRAGMA table_info(users)"))
        XCTAssertFalse(SQLiteQuery.isReadOnly("DELETE FROM users"))
        XCTAssertFalse(SQLiteQuery.isReadOnly("select 1; drop table users"))
        XCTAssertFalse(SQLiteQuery.isReadOnly(".shell ls"))
        XCTAssertFalse(SQLiteQuery.isReadOnly("selectx 1"))
        XCTAssertFalse(SQLiteQuery.isReadOnly("PRAGMA writable_schema=1"))
        XCTAssertFalse(SQLiteQuery.isReadOnly(""))
    }

    func testFileNames() {
        XCTAssertTrue(SQLiteQuery.isValidFileName("app.db"))
        XCTAssertFalse(SQLiteQuery.isValidFileName("app.db-wal"))
        XCTAssertFalse(SQLiteQuery.isValidFileName("../x"))
        XCTAssertFalse(SQLiteQuery.isValidFileName("a b"))
        XCTAssertEqual(SQLiteQuery.quoted("we\"ird"), "\"we\"\"ird\"")
    }

    func testCSVRoundTrip() {
        let text = "id,note\n1,\"hello, \"\"world\"\"\"\n2,\"two\nlines\"\n3,\n"
        let rows = SQLiteQuery.parseCSV(text)
        XCTAssertEqual(rows, [["id", "note"], ["1", "hello, \"world\""], ["2", "two\nlines"], ["3", ""]])
        XCTAssertEqual(SQLiteQuery.parseCSV(SQLiteQuery.csv(rows)), rows)
    }

    func testTableBrowserQueriesAreBuiltSafely() {
        XCTAssertEqual(SQLiteQuery.pageSQL(table: "users", sortColumn: nil, ascending: true, page: 0), "SELECT * FROM \"users\" LIMIT 100 OFFSET 0")
        XCTAssertEqual(SQLiteQuery.pageSQL(table: "we\"ird", sortColumn: "name", ascending: false, page: 2), "SELECT * FROM \"we\"\"ird\" ORDER BY \"name\" DESC LIMIT 100 OFFSET 200")
        XCTAssertTrue(SQLiteQuery.isReadOnly(SQLiteQuery.pageSQL(table: "t", sortColumn: "c", ascending: true, page: 1)))
        XCTAssertNil(SQLiteQuery.countsSQL(tables: []))
        XCTAssertEqual(SQLiteQuery.countsSQL(tables: ["a", "b'c"]), "SELECT 'a' AS name, COUNT(*) AS rows FROM \"a\" UNION ALL SELECT 'b''c' AS name, COUNT(*) AS rows FROM \"b'c\"")
        XCTAssertTrue(SQLiteQuery.isReadOnly(SQLiteQuery.countsSQL(tables: ["a", "b"])!.replacingOccurrences(of: "UNION ALL", with: "UNION ALL")))
    }
}

final class TableFilterTests: XCTestCase {
    func testFiltersAreQuotedAndLikeIsEscaped() {
        XCTAssertEqual(TableFilter(column: "name", operation: .equals, value: "O'Brien").clause, " WHERE \"name\" = 'O''Brien'")
        XCTAssertEqual(TableFilter(column: "name", operation: .contains, value: "50%_x").clause, " WHERE \"name\" LIKE '%50\\%\\_x%' ESCAPE '\\'")
        XCTAssertEqual(TableFilter(column: "n", operation: .isNull).clause, " WHERE \"n\" IS NULL OR \"n\" = ''")
        XCTAssertEqual(TableFilter(column: "", operation: .equals, value: "x").clause, "")
        XCTAssertEqual(TableFilter(column: "a", operation: .greater, value: "").clause, "", "an operator that needs a value is not complete without one")
    }

    func testEveryGeneratedQueryPassesTheReadOnlyCheck() {
        let filter = TableFilter(column: "c", operation: .contains, value: "x")
        XCTAssertTrue(SQLiteQuery.isReadOnly(SQLiteQuery.pageSQL(table: "t", filter: filter, sortColumn: "c", ascending: true, page: 0)))
        XCTAssertTrue(SQLiteQuery.isReadOnly(SQLiteQuery.countSQL(table: "t", filter: filter)))
        XCTAssertTrue(SQLiteQuery.isReadOnly(SQLiteQuery.structureSQL(table: "t")))
        for template in SQLiteQuery.templates(table: "t", columns: ["a"]) { XCTAssertTrue(SQLiteQuery.isReadOnly(template.sql), template.title) }
    }

    func testRoomTablesAreRecognisedAsSystem() {
        XCTAssertTrue(SQLiteQuery.isSystemTable("room_master_table"))
        XCTAssertTrue(SQLiteQuery.isSystemTable("android_metadata"))
        XCTAssertFalse(SQLiteQuery.isSystemTable("users"))
    }

    func testErrorHints() {
        XCTAssertNotNil(SQLiteQuery.hint(forError: "Error: no such table: foo"))
        XCTAssertNil(SQLiteQuery.hint(forError: "something unusual"))
    }
}
