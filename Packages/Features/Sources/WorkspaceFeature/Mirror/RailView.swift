import Components
import DomainModels
import SwiftUI
import Theme

struct RailButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var hint: String?
    var isOn = false
    var tint: Color?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(tint ?? Theme.Palette.text.color)
                .frame(width: Theme.Size.railButton.width, height: Theme.Size.railButton.height)
                .background(isOn ? Theme.Palette.selection : (isHovered ? Theme.Palette.selection.opacity(0.6) : .clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(hint.map { Text(title) + Text(verbatim: "  \($0)") } ?? Text(title))
        .accessibilityLabel(title)
    }
}

public struct ModePicker: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Picker("Mode", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
            ForEach(WorkspaceMode.allCases) { mode in
                Label { Text(mode.title) } icon: { Image(systemName: mode.symbol) }.tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .help("Mode: Normal, Gaming or Developer")
    }
}

struct RailView: View {
    @ObservedObject var model: AppModel
    @Binding var isCollapsed: Bool
    var openLogcat: () -> Void = {}
    var customize: () -> Void = {}

    private static let divider = Theme.Palette.hairline.color
    /// Expanded and collapsed are the same piece of glass, so folding the rail morphs it instead of swapping two views.
    @Namespace private var glassSpace

    var body: some View {
        GlassGroup(spacing: Theme.Space.s6) {
            Group {
                if isCollapsed { collapsed } else { expanded }
            }
        }
        .padding(Theme.Space.s5) // room for the shadow; the panel is transparent
        .fixedSize()
    }

    private var expanded: some View {
        VStack(spacing: Theme.Space.inset) {
            ForEach(Array(model.railLayout.rows(for: model.mode).enumerated()), id: \.offset) { _, row in
                switch row {
                case let .item(item): button(for: item)
                case .separator: separator
                }
            }
            if !model.railLayout.items(for: model.mode).isEmpty { separator }
            RailButton(title: "Disconnect", symbol: "eject") { model.disconnect() }
            Button { withAnimation(Theme.Motion.smooth) { isCollapsed = true } } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary.color)
                    .frame(width: 40, height: 24).contentShape(Capsule())
            }
            .accessibilityLabel("Hide Control Rail")
            .buttonStyle(.plain)
            .help("Hide Control Rail")
            .accessibilityLabel("Hide Control Rail")
        }
        .padding(.vertical, Theme.Space.s2)
        .frame(width: Theme.Size.rail)
        .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Radius.rail), morph: GlassMorph(id: "rail", in: glassSpace))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .contextMenu { Button("Customize Control Rail") { customize() } }
    }

    @ViewBuilder
    private func button(for item: RailItemID) -> some View {
        switch item {
        case .back: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.press(.back) }
        case .home: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.press(.home) }
        case .recents: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.press(.appSwitch) }
        case .volumeUp: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.press(.volumeUp) }
        case .volumeDown: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.press(.volumeDown) }
        case .power: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.press(.power) }
        case .notifications: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.send(.expandNotificationPanel) }
        case .quickSettings: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.send(.expandSettingsPanel) }
        case .rotate: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.send(.rotateDevice) }
        case .screenshot: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.takeScreenshot() }
        case .record:
            RailButton(title: model.isRecording ? "Stop Recording" : item.title, symbol: model.isRecording ? "stop.fill" : item.symbol,
                       isOn: model.isRecording, tint: model.isRecording ? .white : nil) { model.toggleRecording() }
                .background(model.isRecording ? Theme.Palette.redFill.color : .clear, in: Capsule())
        case .mute:
            RailButton(title: model.isMuted ? "Unmute" : item.title, symbol: model.isMuted ? "speaker.slash" : item.symbol,
                       isOn: model.isMuted) { model.toggleMute() }
        case .streamMode: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.isStreamMode = true }
        case .statistics: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint, isOn: model.showsStats) { model.showsStats.toggle() }
        case .keymapToggle: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint, isOn: model.isKeymapEnabled) { model.setKeymapEnabled(!model.isKeymapEnabled) }
        case .keymapProfile:
            Menu {
                if model.keymapProfiles.isEmpty { Text("No keymaps yet") }
                ForEach(model.keymapProfiles) { profile in
                    Button { model.loadKeymap(id: profile.id) } label: {
                        if profile.id == model.currentKeymap?.id { Label(profile.name, systemImage: "checkmark") } else { Text(verbatim: profile.name) }
                    }
                }
            } label: {
                Image(systemName: item.symbol).font(.system(size: 14)).foregroundStyle(Theme.Palette.text.color)
                    .frame(width: Theme.Size.railButton.width, height: Theme.Size.railButton.height)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .help(item.title).accessibilityLabel(item.title)
        case .editKeymap: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { model.startEditingKeymap() }
        case .recordMacro:
            RailButton(title: model.isRecordingMacro ? "Stop Recording Macro" : item.title, symbol: item.symbol, isOn: model.isRecordingMacro) { model.toggleMacroRecording() }
        case .inspector: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint, isOn: model.isInspecting) { model.setInspecting(!model.isInspecting) }
        case .designOverlay:
            RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint, isOn: model.designTool == .crosshair) { model.setDesignTool(model.designTool == .crosshair ? .off : .crosshair) }
        case .colourPicker:
            RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint, isOn: model.designTool == .colorPicker) { model.setDesignTool(model.designTool == .colorPicker ? .off : .colorPicker) }
        case .grid: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint, isOn: model.designGrid != .off) { model.designGrid = Self.nextGrid(after: model.designGrid) }
        case .performanceHUD: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint, isOn: model.showsPerformance) { model.showsPerformance.toggle() }
        case .quickToggles: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint, isOn: model.showsQuickToggles) { model.showsQuickToggles.toggle() }
        case .logcat: RailButton(title: item.title, symbol: item.symbol, hint: item.shortcutHint) { openLogcat() }
        }
    }

    static func nextGrid(after grid: DesignGrid) -> DesignGrid {
        switch grid {
        case .off: return .dp4
        case .dp4: return .dp8
        case .dp8: return .off
        }
    }

    private var separator: some View {
        Rectangle().fill(Self.divider).frame(width: 24, height: 1).padding(.vertical, Theme.Space.s1)
    }

    /// A red dot stays visible while recording.
    private var collapsed: some View {
        Button { withAnimation(Theme.Motion.smooth) { isCollapsed = false } } label: {
            VStack(spacing: Theme.Space.s2) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                if model.isRecording { Circle().fill(Theme.Palette.redFill.color).frame(width: 6, height: 6) }
            }
            .foregroundStyle(Theme.Palette.textSecondary.color)
            .frame(width: 36, height: model.isRecording ? 72 : 56)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(in: Capsule(), morph: GlassMorph(id: "rail", in: glassSpace))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        .help("Show Control Rail")
        .accessibilityLabel("Show Control Rail")
    }
}
