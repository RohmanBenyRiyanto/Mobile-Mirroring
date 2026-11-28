import Components
import SwiftUI
import Theme
import WorkspaceFeature

public struct SettingsView: View {
    @ObservedObject private var model: AppModel
    @ObservedObject private var appearance: AppearanceStore
    @AppStorage("settingsTab") private var tab = Tab.general.rawValue

    enum Tab: String, CaseIterable, Identifiable {
        case general, video, audio, rail, shortcuts, advanced, about
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .general: return "General"
            case .video: return "Video"
            case .audio: return "Audio"
            case .rail: return "Control Rail"
            case .shortcuts: return "Shortcuts"
            case .advanced: return "Advanced"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .video: return "film"
            case .audio: return "speaker.wave.2"
            case .rail: return "sidebar.right"
            case .shortcuts: return "keyboard"
            case .advanced: return "switch.2"
            case .about: return "info.circle"
            }
        }
    }

    public init(model: AppModel, appearance: AppearanceStore) {
        self.model = model
        self.appearance = appearance
    }

    public var body: some View {
        TabView(selection: $tab) {
            ForEach(Tab.allCases) { item in
                page(item)
                    .tabItem { Label { Text(item.title) } icon: { Image(systemName: item.symbol) } }
                    .tag(item.rawValue)
            }
        }
        .frame(width: 560, height: 520)
        .themed(appearance)
    }

    @ViewBuilder
    private func page(_ tab: Tab) -> some View {
        GroupedForm {
            switch tab {
            case .general: GeneralTab(model: model, appearance: appearance)
            case .video: VideoTab(model: model)
            case .audio: AudioTab(model: model)
            case .rail: RailTab(model: model)
            case .shortcuts: ShortcutsTab(model: model)
            case .advanced: AdvancedTab(model: model, appearance: appearance)
            case .about: AboutTab()
            }
        }
    }
}
