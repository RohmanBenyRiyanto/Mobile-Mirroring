import Foundation
import SwiftUI

/// Disconnect and the hide button are not listed here: they are always on the rail.
public enum RailItemID: String, Codable, CaseIterable, Identifiable {
    case back, home, recents
    case volumeUp, volumeDown, power
    case notifications, quickSettings, rotate
    case screenshot, record, mute
    case streamMode, statistics
    case keymapToggle, keymapProfile, editKeymap, recordMacro
    case inspector, designOverlay, colourPicker, grid
    case logcat, performanceHUD, quickToggles, doNotDisturb

    public var id: String { rawValue }

    public enum Group: Int { case navigation, hardware, panels, capture, stream, keymap, inspection, log }

    public var group: Group {
        switch self {
        case .back, .home, .recents: return .navigation
        case .volumeUp, .volumeDown, .power: return .hardware
        case .notifications, .quickSettings, .rotate: return .panels
        case .screenshot, .record, .mute: return .capture
        case .streamMode, .statistics: return .stream
        case .keymapToggle, .keymapProfile, .editKeymap, .recordMacro: return .keymap
        case .inspector, .designOverlay, .colourPicker, .grid: return .inspection
        case .logcat, .performanceHUD, .quickToggles: return .log
        case .doNotDisturb: return .stream
        }
    }

    public var title: LocalizedStringKey {
        switch self {
        case .back: return "Back"
        case .home: return "Home"
        case .recents: return "Recents"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .power: return "Power"
        case .notifications: return "Notifications"
        case .quickSettings: return "Quick Settings"
        case .rotate: return "Rotate"
        case .screenshot: return "Screenshot"
        case .record: return "Record"
        case .mute: return "Mute"
        case .streamMode: return "Stream Mode"
        case .statistics: return "Statistics"
        case .keymapToggle: return "Keymap Enabled"
        case .keymapProfile: return "Keymap Profile"
        case .editKeymap: return "Edit Keymap"
        case .recordMacro: return "Record Macro"
        case .inspector: return "UI Inspector"
        case .designOverlay: return "Design Overlay"
        case .colourPicker: return "Colour Picker"
        case .grid: return "Grid"
        case .logcat: return "Logcat"
        case .performanceHUD: return "Developer HUD"
        case .quickToggles: return "Quick Toggles"
        case .doNotDisturb: return "Do Not Disturb"
        }
    }

    /// One line saying what the button does, shown in the tooltip under its name.
    public var explanation: String {
        switch self {
        case .back: return String(localized: "Go back one screen")
        case .home: return String(localized: "Go to the phone's home screen")
        case .recents: return String(localized: "Show the recent apps")
        case .volumeUp: return String(localized: "Raise the phone's volume")
        case .volumeDown: return String(localized: "Lower the phone's volume")
        case .power: return String(localized: "Turn the phone's screen on or off")
        case .notifications: return String(localized: "Pull down the notifications")
        case .quickSettings: return String(localized: "Pull down the quick settings")
        case .rotate: return String(localized: "Rotate the phone's screen")
        case .screenshot: return String(localized: "Save a picture of the screen to your Mac")
        case .record: return String(localized: "Start or stop recording the screen")
        case .mute: return String(localized: "Silence or restore the phone's sound on this Mac")
        case .streamMode: return String(localized: "Hide the window frame for streaming or capture")
        case .statistics: return String(localized: "Show frame rate, bitrate and delay on the picture")
        case .keymapToggle: return String(localized: "Turn keyboard and mouse controls for games on or off")
        case .keymapProfile: return String(localized: "Switch between your saved game keymaps")
        case .editKeymap: return String(localized: "Place keyboard keys on the phone's screen")
        case .recordMacro: return String(localized: "Record a sequence of touches to replay with a key")
        case .inspector: return String(localized: "Point at an element to see its details")
        case .designOverlay: return String(localized: "Show a crosshair with exact positions")
        case .colourPicker: return String(localized: "Click the picture to read a colour")
        case .grid: return String(localized: "Cycle the 4 dp and 8 dp layout grids")
        case .logcat: return String(localized: "Open the phone's log")
        case .performanceHUD: return String(localized: "Show frame rate, jank, CPU, memory and temperature")
        case .quickToggles: return String(localized: "Developer switches, mock location and network")
        case .doNotDisturb: return String(localized: "Silence calls and banners on the phone while you play")
        }
    }

    /// The menu shortcut shown in the tooltip, kept in step with the menu bar.
    public var shortcutHint: String? {
        switch self {
        case .back: return "⌘["
        case .home: return "⇧⌘H"
        case .recents: return "⇧⌘A"
        case .volumeUp: return "⌘↑"
        case .volumeDown: return "⌘↓"
        case .power: return "⇧⌘P"
        case .notifications: return "⇧⌘N"
        case .quickSettings: return "⌥⌘N"
        case .rotate: return "⌘R"
        case .screenshot: return "⌘S"
        case .record: return "⇧⌘R"
        case .mute: return "⇧⌘M"
        case .streamMode: return "⇧⌘B"
        case .statistics: return "⌘I"
        case .keymapToggle: return "⇧⌘K"
        case .keymapProfile: return nil
        case .editKeymap: return "⌘E"
        case .recordMacro: return nil
        case .inspector: return "⌥⌘I"
        case .designOverlay: return "⌥⌘G"
        case .colourPicker: return nil
        case .grid: return nil
        case .logcat: return "⇧⌘L"
        case .performanceHUD: return "⇧⌘I"
        case .quickToggles: return "⌥⌘J"
        case .doNotDisturb: return nil
        }
    }

    public var symbol: String {
        switch self {
        case .back: return "chevron.backward"
        case .home: return "circle"
        case .recents: return "square"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .power: return "power"
        case .notifications: return "bell"
        case .quickSettings: return "switch.2"
        case .rotate: return "rotate.right"
        case .screenshot: return "camera"
        case .record: return "record.circle"
        case .mute: return "speaker.wave.2"
        case .streamMode: return "rectangle.on.rectangle"
        case .statistics: return "chart.xyaxis.line"
        case .keymapToggle: return "gamecontroller"
        case .keymapProfile: return "list.bullet"
        case .editKeymap: return "slider.horizontal.3"
        case .recordMacro: return "waveform"
        case .inspector: return "cursorarrow.rays"
        case .designOverlay: return "ruler"
        case .colourPicker: return "eyedropper"
        case .grid: return "grid"
        case .logcat: return "text.alignleft"
        case .performanceHUD: return "gauge.with.dots.needle.50percent"
        case .quickToggles: return "wrench.and.screwdriver"
        case .doNotDisturb: return "moon.fill"
        }
    }
}

public enum RailRow: Equatable {
    case item(RailItemID)
    case separator
}

public struct RailLayout: Codable, Equatable {
    private var lists: [String: [RailItemID]]

    public init(lists: [WorkspaceMode: [RailItemID]]) {
        self.lists = Dictionary(uniqueKeysWithValues: lists.map { ($0.key.rawValue, Self.cleaned($0.value)) })
    }

    public static let standard = RailLayout(lists: WorkspaceMode.allCases.reduce(into: [:]) { $0[$1] = defaultItems(for: $1) })

    public static func defaultItems(for mode: WorkspaceMode) -> [RailItemID] {
        switch mode {
        case .normal:
            return [.back, .home, .recents, .volumeUp, .volumeDown, .power, .notifications, .quickSettings, .rotate,
                    .screenshot, .record, .mute, .streamMode, .statistics]
        case .gaming:
            return [.keymapToggle, .keymapProfile, .editKeymap, .recordMacro, .doNotDisturb, .streamMode, .statistics, .screenshot, .record, .mute, .back, .home]
        case .developer:
            return [.inspector, .designOverlay, .colourPicker, .grid, .logcat, .performanceHUD, .quickToggles, .statistics, .screenshot, .record, .mute, .back, .home, .recents]
        }
    }

    public func items(for mode: WorkspaceMode) -> [RailItemID] { lists[mode.rawValue] ?? Self.defaultItems(for: mode) }

    /// Rows in display order, with a separator wherever the group changes.
    public func rows(for mode: WorkspaceMode) -> [RailRow] {
        var rows: [RailRow] = []
        var previous: RailItemID.Group?
        for item in items(for: mode) {
            if let previous, previous != item.group { rows.append(.separator) }
            rows.append(.item(item))
            previous = item.group
        }
        return rows
    }

    public func hidden(in mode: WorkspaceMode) -> [RailItemID] {
        let shown = Set(items(for: mode))
        return RailItemID.allCases.filter { !shown.contains($0) }
    }

    // MARK: Changing it

    public mutating func add(_ item: RailItemID, to mode: WorkspaceMode) {
        var list = items(for: mode)
        guard !list.contains(item) else { return }
        // Next to the tools of its own group when there are any, else at the end.
        if let last = list.lastIndex(where: { $0.group == item.group }) { list.insert(item, at: last + 1) } else { list.append(item) }
        lists[mode.rawValue] = list
    }

    public mutating func remove(_ item: RailItemID, from mode: WorkspaceMode) {
        lists[mode.rawValue] = items(for: mode).filter { $0 != item }
    }

    public mutating func move(_ item: RailItemID, by offset: Int, in mode: WorkspaceMode) {
        var list = items(for: mode)
        guard let index = list.firstIndex(of: item) else { return }
        let target = index + offset
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        lists[mode.rawValue] = list
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, in mode: WorkspaceMode) {
        var list = items(for: mode)
        list.move(fromOffsets: source, toOffset: destination)
        lists[mode.rawValue] = Self.cleaned(list)
    }

    public mutating func reset(_ mode: WorkspaceMode) { lists[mode.rawValue] = Self.defaultItems(for: mode) }

    public var isStandard: Bool { self == Self.standard }

    /// Largest saved layout that is read. A real one is a few hundred bytes; anything bigger is not ours and is ignored.
    public static let maxSavedBytes = 64 * 1024

    /// Nil when the data is too big or is not a layout; the standard layout is used then.
    public static func decode(_ data: Data) -> RailLayout? {
        guard data.count <= maxSavedBytes else { return nil }
        return try? JSONDecoder().decode(RailLayout.self, from: data)
    }

    // MARK: Saved files

    private static func cleaned(_ list: [RailItemID]) -> [RailItemID] {
        var seen = Set<RailItemID>()
        return list.filter { seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey { case lists }

    /// Settings saved by another version may name tools this version does not have, or miss a mode: unknown names are dropped
    /// and a missing mode gets its standard set.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? container.decode([String: [String]].self, forKey: .lists)) ?? [:]
        var lists: [String: [RailItemID]] = [:]
        for mode in WorkspaceMode.allCases {
            lists[mode.rawValue] = raw[mode.rawValue].map { Self.cleaned($0.compactMap(RailItemID.init(rawValue:))) } ?? Self.defaultItems(for: mode)
        }
        self.lists = lists
    }
}
