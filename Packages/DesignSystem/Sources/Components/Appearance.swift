import AppKit
import SwiftUI
import Theme

/// What the user chose under Settings › General › Appearance. Everything defaults to following the system.
public struct AppearanceSettings: Codable, Equatable {
    public enum Mode: String, Codable, CaseIterable, Identifiable {
        case system, light, dark
        public var id: String { rawValue }
    }

    public enum Accent: String, Codable, CaseIterable, Identifiable {
        /// The accent the user picked in System Settings.
        case system
        /// The brand blue (#1E6EF4), whatever the system accent is.
        case benzBlue
        public var id: String { rawValue }
    }

    /// The Dock icon: the one in the app bundle, or one of the glass renders of the icon board.
    public enum DockIcon: String, Codable, CaseIterable, Identifiable {
        case standard, darkBlue, clearBlue, light
        public var id: String { rawValue }

        public var brandVariant: BrandVariant? {
            switch self {
            case .standard: return nil
            case .darkBlue: return .darkBlue
            case .clearBlue: return .clearBlue
            case .light: return .light
            }
        }
    }

    public var mode = Mode.system
    public var accent = Accent.system
    public var surface = SurfaceMode.automatic
    public var dockIcon = DockIcon.standard

    public init(mode: Mode = .system, accent: Accent = .system, surface: SurfaceMode = .automatic, dockIcon: DockIcon = .standard) {
        self.mode = mode
        self.accent = accent
        self.surface = surface
        self.dockIcon = dockIcon
    }

    /// Settings saved by another version miss some fields (or hold values this version does not know); those get the defaults.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? values.decodeIfPresent(Mode.self, forKey: .mode)) ?? .system
        accent = (try? values.decodeIfPresent(Accent.self, forKey: .accent)) ?? .system
        surface = (try? values.decodeIfPresent(SurfaceMode.self, forKey: .surface)) ?? .automatic
        dockIcon = (try? values.decodeIfPresent(DockIcon.self, forKey: .dockIcon)) ?? .standard
    }

    /// The accent to force over the whole interface, or nil to follow the system.
    public var accentColor: Color? {
        accent == .benzBlue ? Color(hex: "#1e6ef4") : nil
    }

    public var colorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Holds the appearance choice, remembers it, and applies it: the appearance of every window, the style of floating surfaces
/// and the Dock icon. The accent is applied by `themed()` on each window's content.
@MainActor
public final class AppearanceStore: ObservableObject {
    @Published public var settings: AppearanceSettings {
        didSet {
            guard settings != oldValue else { return }
            save()
            apply(settings)
        }
    }

    private let defaults: UserDefaults
    private let apply: (AppearanceSettings) -> Void
    private static let key = "appearance.v1"

    /// `apply` is replaceable, so tests never change the real appearance of the machine they run on.
    public init(defaults: UserDefaults = .standard, apply: ((AppearanceSettings) -> Void)? = nil) {
        self.defaults = defaults
        self.apply = apply ?? Self.applyToApp
        settings = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(AppearanceSettings.self, from: $0) } ?? AppearanceSettings()
        self.apply(settings)
    }

    public func reset() { settings = AppearanceSettings() }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.key) }
    }

    /// The real thing: the app's appearance, the surface style and the Dock icon.
    private static func applyToApp(_ settings: AppearanceSettings) {
        SurfaceStyle.mode = settings.surface
        switch settings.mode {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
        NSApp?.applicationIconImage = dockImage(for: settings.dockIcon)
    }

    /// The glass render of the chosen icon, or nil for the icon in the app bundle.
    static func dockImage(for icon: AppearanceSettings.DockIcon) -> NSImage? {
        guard let variant = icon.brandVariant else { return nil }
        let renderer = ImageRenderer(content: BrandTile(size: 512, variant: variant, style: .glass))
        renderer.scale = 2
        return renderer.nsImage
    }
}

private struct Themed: ViewModifier {
    @ObservedObject var store: AppearanceStore

    func body(content: Content) -> some View {
        content
            .tint(store.settings.accentColor)
            .preferredColorScheme(store.settings.colorScheme)
            // Surfaces read the style when they are drawn; a new style rebuilds them.
            .id(store.settings.surface)
    }
}

extension View {
    /// Applies the user's accent, appearance and surface style to a window's content.
    public func themed(_ store: AppearanceStore) -> some View { modifier(Themed(store: store)) }
}
