import Foundation

public struct ForegroundApp: Equatable {
    public let package: String
    public let activity: String

    public init(package: String, activity: String) {
        self.package = package
        self.activity = activity
    }

    public static func isValidPackage(_ name: String) -> Bool {
        let segments = name.split(separator: ".", omittingEmptySubsequences: false)
        return name.count <= 255 && segments.count >= 2 && segments.allSatisfy { segment in
            guard let first = segment.first else { return false }
            return first.isASCII && first.isLetter && segment.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        }
    }
}

public enum ForegroundAppParser {
    public static let command = "dumpsys window displays | grep -E 'mCurrentFocus|mFocusedApp'"

    public static func parse(_ output: String) -> ForegroundApp? {
        for key in ["mFocusedApp=", "mCurrentFocus="] {
            for line in output.split(whereSeparator: \.isNewline) {
                guard let range = line.range(of: key), let app = component(in: line[range.upperBound...]) else { continue }
                return app
            }
        }
        return nil
    }

    private static func component(in text: Substring) -> ForegroundApp? {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "{" || $0 == "}" })
        guard let userIndex = words.firstIndex(where: { isUserToken($0) }), userIndex + 1 < words.count else { return nil }

        let parts = words[userIndex + 1].split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, ForegroundApp.isValidPackage(String(parts[0])), !parts[1].isEmpty else { return nil }
        return ForegroundApp(package: String(parts[0]), activity: String(parts[1]))
    }

    private static func isUserToken(_ word: Substring) -> Bool {
        word.count >= 2 && word.first == "u" && word.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }
}

@MainActor
public final class ForegroundAppDetector: ObservableObject {
    public init() {}

    @Published public private(set) var current: ForegroundApp?

    private var task: Task<Void, Never>?

    public func start(interval: Duration = .seconds(1), fetch: @escaping @Sendable () throws -> String) {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                let output = await Task.detached { try? fetch() }.value
                if let app = output.flatMap(ForegroundAppParser.parse), app != self?.current { self?.current = app }
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        current = nil
    }
}
