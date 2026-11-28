import Foundation

public struct DeviceSettingsBook: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var serial: String
        public var quality: VideoQuality
        public var audioEnabled: Bool
        public var showTouches: Bool
        public var stayAwake: Bool
        public var turnScreenOffOnStart: Bool
    }

    public static let capacity = 64
    public static let maxBytes = 64 * 1024

    public private(set) var entries: [Entry] = []

    public init() {}

    public func apply(to settings: MirrorSettings, serial: String) -> MirrorSettings {
        guard let entry = entries.first(where: { $0.serial == serial }) else { return settings }
        var result = settings
        result.quality = entry.quality
        result.audioEnabled = entry.audioEnabled
        result.showTouches = entry.showTouches
        result.stayAwake = entry.stayAwake
        result.turnScreenOffOnStart = entry.turnScreenOffOnStart
        return result
    }

    public mutating func record(_ settings: MirrorSettings, serial: String) {
        let entry = Entry(serial: serial, quality: settings.quality, audioEnabled: settings.audioEnabled, showTouches: settings.showTouches,
                          stayAwake: settings.stayAwake, turnScreenOffOnStart: settings.turnScreenOffOnStart)
        if let index = entries.firstIndex(where: { $0.serial == serial }) {
            if entries[index] == entry { return }
            entries.remove(at: index)
        }
        entries.append(entry)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    public mutating func forget(serial: String) { entries.removeAll { $0.serial == serial } }

    public static func decode(_ data: Data) -> DeviceSettingsBook? {
        guard data.count <= maxBytes, let book = try? JSONDecoder().decode(DeviceSettingsBook.self, from: data) else { return nil }
        var clean = DeviceSettingsBook()
        for entry in book.entries.suffix(capacity) where entry.serial.count <= 128 { clean.entries.append(entry) }
        return clean
    }
}
