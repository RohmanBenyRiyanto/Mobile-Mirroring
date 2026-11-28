import Foundation

public enum SQLiteQuery {
    /// Only plain reads are allowed: one SELECT/WITH/EXPLAIN statement or a table-info PRAGMA. The database is also opened read-only.
    public static func isReadOnly(_ sql: String) -> Bool {
        var text = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix(";") { text.removeLast(); text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !text.isEmpty, !text.contains(";"), !text.hasPrefix(".") else { return false }
        let lower = text.lowercased()
        if lower.hasPrefix("pragma") { return lower.hasPrefix("pragma table_info(") || lower.hasPrefix("pragma table_list") }
        return ["select", "with", "explain"].contains { lower.hasPrefix($0) && (lower.dropFirst($0.count).first.map { !$0.isLetter && !$0.isNumber && $0 != "_" } ?? true) }
    }

    public static func isValidFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128, !name.hasPrefix("."),
              name.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else { return false }
        return !["-journal", "-wal", "-shm"].contains { name.hasSuffix($0) }
    }

    /// A table name safe to put inside double quotes.
    public static func quoted(_ identifier: String) -> String { "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    /// RFC 4180 style CSV as printed by `sqlite3 -csv`: quoted fields, doubled quotes, line breaks inside quotes.
    public static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false, sawContent = false
        var iterator = text.makeIterator()
        var pending: Character?
        func next() -> Character? { if let p = pending { pending = nil; return p }; return iterator.next() }
        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let following = iterator.next() { if following == "\"" { field.append("\"") } else { inQuotes = false; pending = following } } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true; sawContent = true
                case ",": row.append(field); field = ""; sawContent = true
                case "\n", "\r\n":
                    if sawContent || !field.isEmpty { row.append(field); rows.append(row) }
                    row = []; field = ""; sawContent = false
                default: field.append(c); sawContent = true
                }
            }
        }
        if sawContent || !field.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    public static func csv(_ rows: [[String]]) -> String {
        rows.map { $0.map { cell in cell.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : cell }.joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }
}

// MARK: Building queries for the table browser

extension SQLiteQuery {
    public static let pageSize = 100

    /// One page of a table, optionally sorted. Names are quoted, numbers are plain integers: nothing typed by the user is spliced in.
    public static func pageSQL(table: String, sortColumn: String?, ascending: Bool, page: Int) -> String {
        var sql = "SELECT * FROM \(quoted(table))"
        if let sortColumn { sql += " ORDER BY \(quoted(sortColumn)) \(ascending ? "ASC" : "DESC")" }
        return sql + " LIMIT \(pageSize) OFFSET \(max(page, 0) * pageSize)"
    }

    /// Row counts for several tables in one go: `table name, count`.
    public static func countsSQL(tables: [String]) -> String? {
        guard !tables.isEmpty else { return nil }
        return tables.map { "SELECT \(quotedLiteral($0)) AS name, COUNT(*) AS rows FROM \(quoted($0))" }.joined(separator: " UNION ALL ")
    }

    public static let schemaSQL = "SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name"

    /// A string literal for SQL (single quotes doubled).
    static func quotedLiteral(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "''") + "'" }
}

// MARK: Filters, structure and helpers for the query form

/// A "column operator value" condition built from form fields. The column is quoted and the value is a quoted literal.
public struct TableFilter: Equatable, Sendable {
    public enum Operation: String, CaseIterable, Identifiable, Sendable {
        case equals, notEquals, contains, startsWith, greater, less, isNull, isNotNull
        public var id: String { rawValue }
        public var needsValue: Bool { self != .isNull && self != .isNotNull }
        public var symbol: String {
            switch self {
            case .equals: return "="
            case .notEquals: return "≠"
            case .contains: return "contains"
            case .startsWith: return "starts with"
            case .greater: return ">"
            case .less: return "<"
            case .isNull: return "is empty"
            case .isNotNull: return "is not empty"
            }
        }
    }

    public var column: String
    public var operation: Operation
    public var value: String

    public init(column: String, operation: Operation, value: String = "") {
        self.column = column
        self.operation = operation
        self.value = value
    }

    public var isComplete: Bool { !column.isEmpty && (!operation.needsValue || !value.isEmpty) }

    /// `WHERE …` for this filter, or an empty string when it is not complete.
    public var clause: String {
        guard isComplete else { return "" }
        let name = SQLiteQuery.quoted(column)
        let literal = SQLiteQuery.quotedLiteral(value)
        switch operation {
        case .equals: return " WHERE \(name) = \(literal)"
        case .notEquals: return " WHERE \(name) <> \(literal)"
        case .contains: return " WHERE \(name) LIKE \(SQLiteQuery.quotedLiteral("%" + SQLiteQuery.escapeLike(value) + "%")) ESCAPE '\\'"
        case .startsWith: return " WHERE \(name) LIKE \(SQLiteQuery.quotedLiteral(SQLiteQuery.escapeLike(value) + "%")) ESCAPE '\\'"
        case .greater: return " WHERE \(name) > \(literal)"
        case .less: return " WHERE \(name) < \(literal)"
        case .isNull: return " WHERE \(name) IS NULL OR \(name) = ''"
        case .isNotNull: return " WHERE \(name) IS NOT NULL AND \(name) <> ''"
        }
    }
}

extension SQLiteQuery {
    /// `%`, `_` and the escape character are matched literally in a LIKE pattern.
    static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
    }

    public static func pageSQL(table: String, filter: TableFilter?, sortColumn: String?, ascending: Bool, page: Int) -> String {
        var sql = "SELECT * FROM \(quoted(table))" + (filter?.clause ?? "")
        if let sortColumn { sql += " ORDER BY \(quoted(sortColumn)) \(ascending ? "ASC" : "DESC")" }
        return sql + " LIMIT \(pageSize) OFFSET \(max(page, 0) * pageSize)"
    }

    public static func countSQL(table: String, filter: TableFilter?) -> String { "SELECT COUNT(*) FROM \(quoted(table))" + (filter?.clause ?? "") }

    public static func structureSQL(table: String) -> String { "PRAGMA table_info(\(quoted(table)))" }

    /// Tables Room and Android create for themselves; shown dimmed so app tables stand out.
    public static func isSystemTable(_ name: String) -> Bool {
        name == "android_metadata" || name == "room_master_table" || name == "sqlite_sequence" || name.hasPrefix("sqlite_") || name.hasPrefix("room_")
            || name.hasSuffix("_fts_content") || name.hasSuffix("_fts_segments") || name.hasSuffix("_fts_segdir") || name.hasSuffix("_fts_docsize") || name.hasSuffix("_fts_stat")
    }

    /// Ready-made queries for a starting point; the table and column names are quoted.
    public static func templates(table: String?, columns: [String]) -> [(title: String, sql: String)] {
        guard let table else { return [("Tables and views", "SELECT name, type FROM sqlite_master ORDER BY type, name")] }
        let t = quoted(table)
        var list = [
            ("All rows", "SELECT * FROM \(t) LIMIT 100"),
            ("Count rows", "SELECT COUNT(*) FROM \(t)"),
            ("Structure", "PRAGMA table_info(\(t))"),
            ("Tables and views", "SELECT name, type FROM sqlite_master ORDER BY type, name"),
        ]
        if let first = columns.first {
            let c = quoted(first)
            list.append(("Count by \(first)", "SELECT \(c), COUNT(*) AS count FROM \(t) GROUP BY \(c) ORDER BY count DESC LIMIT 100"))
            list.append(("Distinct \(first)", "SELECT DISTINCT \(c) FROM \(t) LIMIT 100"))
        }
        return list
    }

    /// A plain-language hint for the errors people hit most when writing a query.
    public static func hint(forError message: String) -> String? {
        let lower = message.lowercased()
        if lower.contains("no such table") { return "That table does not exist in this database. Pick one from the list on the left." }
        if lower.contains("no such column") { return "That column does not exist. Open the table's Structure to see its columns." }
        if lower.contains("syntax error") { return "The query is not valid SQL. Check commas, quotes and keywords." }
        if lower.contains("database is locked") { return "The app is writing to the database right now. Try again in a moment." }
        if lower.contains("malformed") || lower.contains("not a database") { return "The file could not be read as a database. It may be encrypted or mid-write." }
        return nil
    }
}
