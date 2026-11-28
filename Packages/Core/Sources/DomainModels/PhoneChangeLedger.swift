import Foundation

public struct PhoneChangeLedger: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var baseline: DeveloperState?
        public var mockLocationActive = false

        public var isClean: Bool { baseline == nil && !mockLocationActive }
    }

    public static let maxPhones = 64
    public static let maxBytes = 64 * 1024

    private var entries: [String: Entry] = [:]

    public init() {}

    public func entry(for serial: String) -> Entry? { entries[serial] }

    public mutating func recordBaseline(_ baseline: DeveloperState, for serial: String) {
        var entry = entries[serial] ?? Entry()
        if entry.baseline == nil { entry.baseline = baseline }
        store(entry, for: serial)
    }

    public mutating func setMockLocation(_ active: Bool, for serial: String) {
        var entry = entries[serial] ?? Entry()
        entry.mockLocationActive = active
        store(entry, for: serial)
    }

    public mutating func clearBaseline(for serial: String) {
        guard var entry = entries[serial] else { return }
        entry.baseline = nil
        store(entry, for: serial)
    }

    public mutating func clear(_ serial: String) { entries[serial] = nil }

    private mutating func store(_ entry: Entry, for serial: String) {
        if entry.isClean { entries[serial] = nil; return }
        entries[serial] = entry
        if entries.count > Self.maxPhones, let drop = entries.keys.first(where: { $0 != serial }) { entries[drop] = nil }
    }

    public static func restoreCommands(for entry: Entry, current: DeveloperState) -> [String] {
        var commands: [String] = []
        if entry.mockLocationActive { commands.append(MockLocation.stopCommand) }
        if let baseline = entry.baseline { commands += DeveloperSettings.commands(from: current, to: baseline) }
        return commands
    }

    public static func decode(_ data: Data) -> PhoneChangeLedger? {
        guard data.count <= maxBytes else { return nil }
        return try? JSONDecoder().decode(PhoneChangeLedger.self, from: data)
    }
}
