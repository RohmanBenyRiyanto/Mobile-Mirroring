import Foundation

public enum ProcessList {
    /// Fixed command text; nothing user-supplied reaches the phone's shell.
    public static let command = "ps -A -o PID,NAME"

    /// Reads `ps -A -o PID,NAME` output (a header line, then `  PID NAME` per line).
    public static func parse(_ output: String) -> [(pid: Int, name: String)] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2, let pid = Int(fields[0]) else { return nil } // the header and odd lines are skipped
            return (pid, fields[1].trimmingCharacters(in: .whitespaces))
        }
    }

    /// The pids of `package`: its main process (`com.game`) and its named processes (`com.game:push`), but not
    /// another app whose name merely starts the same way (`com.game.helper`).
    public static func pids(of package: String, in processes: [(pid: Int, name: String)]) -> Set<Int> {
        Set(processes.filter { $0.name == package || $0.name.hasPrefix(package + ":") }.map(\.pid))
    }
}

public enum LogScope {
    /// A line belongs to the app if it comes from one of its processes, mentions its package (system messages such as
    /// "Process … has died"), or is part of a crash report that was already accepted.
    public static func accepts(_ entry: LogEntry, package: String, pids: Set<Int>, acceptedBlocks: Set<Int>) -> Bool {
        if let pid = entry.pid, pids.contains(pid) { return true }
        if entry.message.contains(package) { return true }
        if let block = entry.crashBlock, acceptedBlocks.contains(block) { return true }
        return false
    }

    /// The pid in a crash report's `Process: com.game, PID: 1234` line, if the line is for `package`.
    public static func crashPID(in message: String, package: String) -> Int? {
        let prefix = "Process: \(package), PID: "
        guard let range = message.range(of: prefix) else { return nil }
        return Int(message[range.upperBound...].prefix { $0.isNumber })
    }
}
