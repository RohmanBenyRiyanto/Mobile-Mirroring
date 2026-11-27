import Foundation

public enum LogLevel: Int, CaseIterable, Identifiable, Comparable {
    case verbose, debug, info, warning, error, fatal

    public var id: Int { rawValue }

    public var letter: Character { Array("VDIWEF")[rawValue] }

    public var title: String {
        switch self {
        case .verbose: return "Verbose"
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .fatal: return "Fatal"
        }
    }

    public init?(letter: Character) {
        guard let index = "VDIWEF".firstIndex(of: letter) else { return nil }
        self.init(rawValue: "VDIWEF".distance(from: "VDIWEF".startIndex, to: index))
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct LogEntry: Identifiable, Equatable {
    /// What a line is part of, so crashes and stack traces can be picked out of the noise.
    public enum Kind: Equatable {
        case normal
        /// `FATAL EXCEPTION`: the start of a Java/Kotlin crash.
        case crash
        case exception
        case causedBy
        /// `at com.example.Foo.bar(Foo.kt:12)` or a native `#00 pc …` frame.
        case stackFrame
        /// `Fatal signal 11`: the start of a native crash.
        case nativeCrash
        case anr
        case processDied

        public var startsCrash: Bool { self == .crash || self == .nativeCrash || self == .anr }
    }

    public let id: Int
    public let level: LogLevel
    public let text: String
    public var pid: Int?
    public var tag = ""
    public var message = ""
    public var kind = Kind.normal
    /// Lines of one crash share a block number, so they can be drawn together.
    public var crashBlock: Int?

    /// Parses `logcat -v threadtime`: `MM-DD HH:MM:SS.mmm PID TID L Tag: message`.
    /// Anything else (a wrapped line, a banner such as `--- beginning of crash`) is kept as verbose text.
    public static func parse(_ line: String, id: Int) -> LogEntry {
        let fields = line.split(maxSplits: 5, whereSeparator: \.isWhitespace)
        guard fields.count == 6, fields[4].count == 1, let letter = fields[4].first, let level = LogLevel(letter: letter) else {
            return LogEntry(id: id, level: .verbose, text: line)
        }

        // The tag is padded with spaces and ends at the first ": ".
        let rest = String(fields[5])
        var tag = "", message = rest
        if let separator = rest.range(of: ": ") {
            tag = rest[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            message = String(rest[separator.upperBound...])
        } else if rest.hasSuffix(":") {
            tag = String(rest.dropLast()).trimmingCharacters(in: .whitespaces)
            message = ""
        }

        return LogEntry(id: id, level: level, text: line, pid: Int(fields[2]), tag: tag, message: message,
                        kind: CrashDetector.kind(level: level, tag: tag, message: message))
    }
}

/// Reassembles lines from arbitrary chunks of process output.
public struct LineBuffer {

    public init() {

    }
    private var partial = Data()

    /// Returns the lines completed by `chunk`; an unfinished last line is kept for the next call.
    public mutating func append(_ chunk: Data) -> [String] {
        partial.append(chunk)
        var lines: [String] = []
        while let newline = partial.firstIndex(of: 0x0A) {
            let line = partial[partial.startIndex..<newline]
            lines.append(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .newlines))
            partial = Data(partial[(newline + 1)...])
        }
        return lines
    }
}
