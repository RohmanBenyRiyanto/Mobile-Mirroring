import Foundation

public enum CrashDetector {
    public static func kind(level: LogLevel, tag: String, message: String) -> LogEntry.Kind {
        let trimmed = message.trimmingCharacters(in: .whitespaces)

        switch tag {
        case "AndroidRuntime":
            if trimmed.hasPrefix("FATAL EXCEPTION") { return .crash }
            if trimmed.hasPrefix("Caused by:") { return .causedBy }
            if isStackFrame(trimmed) { return .stackFrame }
            return isExceptionLine(trimmed) ? .exception : .normal
        case "libc":
            if trimmed.hasPrefix("Fatal signal") { return .nativeCrash }
        case "DEBUG":
            if trimmed.hasPrefix("#"), trimmed.contains(" pc ") { return .stackFrame }
        case "ActivityManager":
            if trimmed.hasPrefix("ANR in ") { return .anr }
            if trimmed.hasPrefix("Process "), trimmed.contains(" has died") { return .processDied }
        default:
            break
        }

        if trimmed.hasPrefix("Caused by:") { return .causedBy }
        if message.hasPrefix("\tat "), isStackFrame(trimmed) { return .stackFrame }
        return .normal
    }

    public static func isStackFrame(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("at "), trimmed.contains("("), trimmed.hasSuffix(")") { return true }
        guard trimmed.hasPrefix("... "), trimmed.hasSuffix(" more") else { return false }
        return Int(trimmed.dropFirst(4).dropLast(5)) != nil
    }

    public static func isExceptionLine(_ trimmed: String) -> Bool {
        guard let first = trimmed.split(whereSeparator: \.isWhitespace).first else { return false }
        let name = first.hasSuffix(":") ? first.dropLast() : first
        return name.contains(".") && (name.contains("Exception") || name.hasSuffix("Error")) && !name.contains("/")
    }
}

public struct CrashGrouper {
    public init() {
    }
    private var open: (pid: Int, block: Int, tags: Set<String>)?
    private var nextBlock = 0

    public mutating func apply(to entry: LogEntry) -> LogEntry {
        var entry = entry
        if entry.kind.startsCrash {
            nextBlock += 1
            open = (entry.pid ?? -1, nextBlock, [entry.tag])
            entry.crashBlock = nextBlock
            return entry
        }
        guard let open else { return entry }

        switch entry.kind {
        case .exception, .causedBy, .stackFrame:
            if entry.pid == open.pid || open.tags.contains(entry.tag) || entry.tag == "DEBUG" { entry.crashBlock = open.block }
        case .normal, .processDied:
            if entry.pid == open.pid, open.tags.contains(entry.tag) {
                entry.crashBlock = open.block
            } else if entry.tag == "DEBUG", open.tags.contains("libc") {
                entry.crashBlock = open.block
            } else if entry.pid == open.pid {
                self.open = nil
            }
        case .crash, .nativeCrash, .anr:
            break
        }
        return entry
    }
}
