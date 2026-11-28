import AppKit
import SwiftUI
import Theme

/// Appearance preferences. Every setting defaults to following the system.
public struct AppearanceSettings: Codable, Equatable {
    public enum Mode: String, Codable, CaseIterable, Identifiable {
        case system, light, dark
        public var id: String { rawValue }
    }

    public enum Accent: String, Codable, CaseIterable, Identifiable {
        case system
        case benzBlue
        public var id: String { rawValue }
    }

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

    /// Saved settings may miss fields or hold unknown values from other versions; those fall back to defaults.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = (try? values.decodeIfPresent(Mode.self, forKey: .mode)) ?? .system
        accent = (try? values.decodeIfPresent(Accent.self, forKey: .accent)) ?? .system
        surface = (try? values.decodeIfPresent(SurfaceMode.self, forKey: .surface)) ?? .automatic
        dockIcon = (try? values.decodeIfPresent(DockIcon.self, forKey: .dockIcon)) ?? .standard
    }

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

/// Stores the appearance choice in UserDefaults and applies it to the app.
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

    /// `apply` is injectable so tests do not change the real appearance.
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

    private static func applyToApp(_ settings: AppearanceSettings) {
        SurfaceStyle.mode = settings.surface
        switch settings.mode {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
        NSApp?.applicationIconImage = dockImage(for: settings.dockIcon)
    }

    static func dockImage(for icon: AppearanceSettings.DockIcon) -> NSImage? {
        guard let variant = icon.brandVariant else { return nil }
        // The 3D glass renders from the design are in the app's asset catalog; drawing the tile is only the fallback (tests, previews).
        let asset: String
        switch icon {
        case .standard: return nil
        case .darkBlue: asset = "DockIconDarkBlue"
        case .clearBlue: asset = "DockIconClearBlue"
        case .light: asset = "DockIconLight"
        }
        if let image = NSImage(named: asset) { return image }
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
            // Surfaces read their style when drawn, so a new style needs a rebuild.
            .id(store.settings.surface)
    }
}

extension View {
    public func themed(_ store: AppearanceStore) -> some View { modifier(Themed(store: store)) }
}
