import Foundation

public struct Profile<Payload: Codable & Equatable>: Equatable {
    public var id: String
    public var name: String
    public var payload: Payload
    public var modified = Date()

    public init(id: String, name: String, payload: Payload, modified: Date = Date()) {
        self.id = id
        self.name = name
        self.payload = payload
        self.modified = modified
    }
}

public struct ProfileSummary: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let modified: Date

    public init(id: String, name: String, modified: Date) {
        self.id = id
        self.name = name
        self.modified = modified
    }
}

public enum ProfileFormat {
    public static let name = "benzmirror.profile"
    public static let version = 1
    public static let maxBytes = 1 << 20
    public static let maxNameLength = 120

    public static func isValidIdentifier(_ text: String) -> Bool {
        (1...128).contains(text.count) && !text.hasPrefix(".") && !text.contains("..")
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }
    }

    public static func cleanName(_ text: String, fallback: String) -> String {
        let printable = String(text.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }.map(Character.init))
        let trimmed = printable.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(maxNameLength))
    }
}

public enum ProfileError: LocalizedError, Equatable {
    case invalidIdentifier(String)
    case notFound(String)
    case tooLarge
    case notAProfile
    case wrongKind(expected: String, found: String)
    case newerVersion(Int)
    case corrupt(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidIdentifier(id): return "\"\(id)\" is not a valid profile name. Use letters, digits, dots, dashes and underscores."
        case let .notFound(id): return "Profile \"\(id)\" does not exist."
        case .tooLarge: return "This file is too large to be a profile."
        case .notAProfile: return "This file is not a Benz Mirror profile."
        case let .wrongKind(expected, found): return "This is a \(found) profile, but a \(expected) profile was expected."
        case let .newerVersion(version): return "This profile was made by a newer version of Benz Mirror (format \(version))."
        case let .corrupt(detail): return "The profile is damaged: \(detail)"
        }
    }
}

public final class ProfileStore<Payload: Codable & Equatable> {
    public let kind: String
    public let directory: URL
    private let files = FileManager.default

    private struct Header: Decodable {
        let format: String
        let version: Int
        let kind: String
    }

    private struct Envelope: Codable {
        var format = ProfileFormat.name
        var version = ProfileFormat.version
        var kind: String
        var id: String
        var name: String
        var modified: Date
        var payload: Payload
    }

    public static func defaultRoot(appName: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }

    public init(kind: String, root: URL) throws {
        guard ProfileFormat.isValidIdentifier(kind) else { throw ProfileError.invalidIdentifier(kind) }
        self.kind = kind
        directory = root.appendingPathComponent(kind, isDirectory: true)
    }

    // MARK: Reading

    public func list() -> [ProfileSummary] {
        let names = (try? files.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { fileName -> ProfileSummary? in
            guard fileName.hasSuffix(".json") else { return nil }
            let id = String(fileName.dropLast(".json".count))
            guard let profile = try? load(id: id) else { return nil }
            return ProfileSummary(id: id, name: profile.name, modified: profile.modified)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func loadAll() -> [Profile<Payload>] {
        ((try? files.contentsOfDirectory(atPath: directory.path)) ?? []).compactMap { fileName in
            fileName.hasSuffix(".json") ? try? load(id: String(fileName.dropLast(".json".count))) : nil
        }
    }

    public func load(id: String) throws -> Profile<Payload> {
        let url = try fileURL(for: id)
        guard files.fileExists(atPath: url.path) else { throw ProfileError.notFound(id) }
        let size = (try? files.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size <= ProfileFormat.maxBytes else { throw ProfileError.tooLarge }
        return try decode(try Data(contentsOf: url))
    }

    // MARK: Writing

    @discardableResult
    public func save(_ profile: Profile<Payload>) throws -> Profile<Payload> {
        let url = try fileURL(for: profile.id)
        var saved = profile
        saved.name = ProfileFormat.cleanName(profile.name, fallback: profile.id)
        saved.modified = Date()

        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encode(saved).write(to: url, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return saved
    }

    public func delete(id: String) throws {
        let url = try fileURL(for: id)
        guard files.fileExists(atPath: url.path) else { throw ProfileError.notFound(id) }
        try files.removeItem(at: url)
    }

    // MARK: Sharing

    public func exportData(id: String) throws -> Data {
        try encode(try load(id: id))
    }

    public func inspect(_ data: Data) throws -> Profile<Payload> {
        try decode(data)
    }

    public func identifiers() -> Set<String> {
        Set(((try? files.contentsOfDirectory(atPath: directory.path)) ?? []).compactMap {
            $0.hasSuffix(".json") ? String($0.dropLast(".json".count)) : nil
        })
    }

    public func contains(id: String) -> Bool {
        guard let url = try? fileURL(for: id) else { return false }
        return files.fileExists(atPath: url.path)
    }

    @discardableResult
    public func importData(_ data: Data, overwrite: Bool = false) throws -> Profile<Payload> {
        var profile = try decode(data)
        if !overwrite { profile.id = try freeIdentifier(startingWith: profile.id) }
        return try save(profile)
    }

    // MARK: Encoding

    private func encode(_ profile: Profile<Payload>) throws -> Data {
        let envelope = Envelope(kind: kind, id: profile.id, name: profile.name, modified: profile.modified, payload: profile.payload)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    private func decode(_ data: Data) throws -> Profile<Payload> {
        guard data.count <= ProfileFormat.maxBytes else { throw ProfileError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let header = try? decoder.decode(Header.self, from: data), header.format == ProfileFormat.name else {
            throw ProfileError.notAProfile
        }
        guard header.version <= ProfileFormat.version else { throw ProfileError.newerVersion(header.version) }
        guard header.kind == kind else { throw ProfileError.wrongKind(expected: kind, found: header.kind) }

        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) } catch {
            throw ProfileError.corrupt((error as? DecodingError).map(Self.describe) ?? error.localizedDescription)
        }
        guard ProfileFormat.isValidIdentifier(envelope.id) else { throw ProfileError.invalidIdentifier(envelope.id) }
        return Profile(id: envelope.id, name: ProfileFormat.cleanName(envelope.name, fallback: envelope.id),
                       payload: envelope.payload, modified: envelope.modified)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, _): return "missing \"\(key.stringValue)\""
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default: return "unreadable data"
        }
    }

    // MARK: Paths

    private func fileURL(for id: String) throws -> URL {
        guard ProfileFormat.isValidIdentifier(id) else { throw ProfileError.invalidIdentifier(id) }
        return directory.appendingPathComponent("\(id).json")
    }

    private func freeIdentifier(startingWith id: String) throws -> String {
        guard files.fileExists(atPath: try fileURL(for: id).path) else { return id }
        for number in 2...999 {
            let candidate = "\(id)-\(number)"
            if ProfileFormat.isValidIdentifier(candidate), !files.fileExists(atPath: directory.appendingPathComponent("\(candidate).json").path) {
                return candidate
            }
        }
        throw ProfileError.corrupt("too many profiles share the name \"\(id)\"")
    }
}
