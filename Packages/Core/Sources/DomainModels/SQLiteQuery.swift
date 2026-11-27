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
