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
}
