import Foundation

/// Recognises the lines of crashes, ANRs and stack traces in logcat output.
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

        // Exceptions that an app prints itself (e.printStackTrace) come under the app's own tag.
        if trimmed.hasPrefix("Caused by:") { return .causedBy }
        if message.hasPrefix("\tat "), isStackFrame(trimmed) { return .stackFrame }
        return .normal
    }

    /// `at com.example.Foo.bar(Foo.kt:12)` or `... 12 more`.
    public static func isStackFrame(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("at "), trimmed.contains("("), trimmed.hasSuffix(")") { return true }
        guard trimmed.hasPrefix("... "), trimmed.hasSuffix(" more") else { return false }
        return Int(trimmed.dropFirst(4).dropLast(5)) != nil
    }

    /// `android.app.RemoteServiceException$CrashedByAdbException: shell-induced crash`
    public static func isExceptionLine(_ trimmed: String) -> Bool {
        guard let first = trimmed.split(whereSeparator: \.isWhitespace).first else { return false }
        let name = first.hasSuffix(":") ? first.dropLast() : first
        return name.contains(".") && (name.contains("Exception") || name.hasSuffix("Error")) && !name.contains("/")
    }
}

/// Numbers the lines of each crash so they can be shown together, even when other processes log in between.
public struct CrashGrouper {

    public init() {

    }
    private var open: (pid: Int, block: Int, tags: Set<String>)?
    private var nextBlock = 0

    /// Returns `entry` with its crash block set, if it belongs to one.
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
            // A native trace is printed by another process (`DEBUG`), so a frame from a tag the crash used also belongs.
            if entry.pid == open.pid || open.tags.contains(entry.tag) || entry.tag == "DEBUG" { entry.crashBlock = open.block }
        case .normal, .processDied:
            if entry.pid == open.pid, open.tags.contains(entry.tag) {
                entry.crashBlock = open.block // "Process: …, PID: …" lines of the same report
            } else if entry.tag == "DEBUG", open.tags.contains("libc") {
                entry.crashBlock = open.block // the rest of a native report
            } else if entry.pid == open.pid {
                self.open = nil // the same process went on to log something else: the report is over
            }
        case .crash, .nativeCrash, .anr:
            break
        }
        return entry
    }
}
