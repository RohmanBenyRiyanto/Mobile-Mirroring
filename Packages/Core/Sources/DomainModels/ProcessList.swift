import Foundation

public enum ProcessList {
    public static let command = "ps -A -o PID,NAME"

    public static func parse(_ output: String) -> [(pid: Int, name: String)] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, let pid = Int(fields[0]) else { return nil }
            return (pid, fields[1].trimmingCharacters(in: .whitespaces))
        }
    }

    public static func pids(of package: String, in processes: [(pid: Int, name: String)]) -> Set<Int> {
        Set(processes.filter { $0.name == package || $0.name.hasPrefix(package + ":") }.map(\.pid))
    }
}

public enum LogScope {
    public static func accepts(_ entry: LogEntry, package: String, pids: Set<Int>, acceptedBlocks: Set<Int>) -> Bool {
        if let pid = entry.pid, pids.contains(pid) { return true }
        if entry.message.contains(package) { return true }
        if let block = entry.crashBlock, acceptedBlocks.contains(block) { return true }
        return false
    }

    public static func crashPID(in message: String, package: String) -> Int? {
        let prefix = "Process: \(package), PID: "
        guard let range = message.range(of: prefix) else { return nil }
        return Int(message[range.upperBound...].prefix { $0.isNumber })
    }
}
