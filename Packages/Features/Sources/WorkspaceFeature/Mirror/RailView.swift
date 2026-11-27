import Components
import DomainModels
import SwiftUI
import Theme

/// One button of the control rail. 40 × 36, round; it lights up while its feature is on.
struct RailButton: View {
    let title: LocalizedStringKey
    let symbol: String
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
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The three modes as a picker, for the Connect window's toolbar. Icons only, with the names as tooltips.
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

/// The control rail: a glass capsule that floats beside the mirror window. Its tools follow the mode:
/// Normal for everyday use, Gaming for keymap and streaming, Developer for inspecting an app.
struct RailView: View {
    @ObservedObject var model: AppModel
    @Binding var isCollapsed: Bool
    var openLogcat: () -> Void = {}

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
            switch model.mode {
            case .normal: normalTools
            case .gaming: gamingTools
            case .developer: developerTools
            }
            separator
            RailButton(title: "Disconnect", symbol: "eject") { model.disconnect() }
            Button { withAnimation(Theme.Motion.smooth) { isCollapsed = true } } label: {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textSecondary.color)
                    .frame(width: 40, height: 24).contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Hide Control Rail")
            .accessibilityLabel("Hide Control Rail")
        }
        .padding(.vertical, Theme.Space.s2)
        .frame(width: Theme.Size.rail)
        .glassSurface(in: RoundedRectangle(cornerRadius: Theme.Radius.rail), morph: GlassMorph(id: "rail", in: glassSpace))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }

    // MARK: Modes (chosen in Mirror ▸ Mode; the rail only follows)

    @ViewBuilder
    private var normalTools: some View {
        navigationButtons
        separator
        RailButton(title: "Volume Up", symbol: "speaker.wave.3") { model.press(.volumeUp) }
        RailButton(title: "Volume Down", symbol: "speaker.wave.1") { model.press(.volumeDown) }
        RailButton(title: "Power", symbol: "power") { model.press(.power) }
        separator
        RailButton(title: "Notifications", symbol: "bell") { model.send(.expandNotificationPanel) }
        RailButton(title: "Quick Settings", symbol: "switch.2") { model.send(.expandSettingsPanel) }
        RailButton(title: "Rotate", symbol: "rotate.right") { model.send(.rotateDevice) }
        separator
        captureButtons
        separator
        RailButton(title: "Stream Mode", symbol: "rectangle.on.rectangle") { model.isStreamMode = true }
        RailButton(title: "Statistics", symbol: "chart.xyaxis.line", isOn: model.showsStats) { model.showsStats.toggle() }
    }

    @ViewBuilder
    private var gamingTools: some View {
        RailButton(title: "Keymap Enabled", symbol: "gamecontroller", isOn: model.isKeymapEnabled) { model.setKeymapEnabled(!model.isKeymapEnabled) }
        RailButton(title: "Edit Keymap", symbol: "slider.horizontal.3") { model.startEditingKeymap() }
        RailButton(title: model.isRecordingMacro ? "Stop Recording Macro" : "Record Macro", symbol: "waveform", isOn: model.isRecordingMacro) { model.toggleMacroRecording() }
        separator
        RailButton(title: "Stream Mode", symbol: "rectangle.on.rectangle") { model.isStreamMode = true }
        RailButton(title: "Statistics", symbol: "chart.xyaxis.line", isOn: model.showsStats) { model.showsStats.toggle() }
        separator
        captureButtons
        separator
        RailButton(title: "Back", symbol: "chevron.backward") { model.press(.back) }
        RailButton(title: "Home", symbol: "circle") { model.press(.home) }
    }

    @ViewBuilder
    private var developerTools: some View {
        RailButton(title: "UI Inspector", symbol: "cursorarrow.rays", isOn: model.isInspecting) { model.setInspecting(!model.isInspecting) }
        RailButton(title: "Design Overlay", symbol: "ruler", isOn: model.designTool == .crosshair) { model.setDesignTool(model.designTool == .crosshair ? .off : .crosshair) }
        RailButton(title: "Colour Picker", symbol: "eyedropper", isOn: model.designTool == .colorPicker) { model.setDesignTool(model.designTool == .colorPicker ? .off : .colorPicker) }
        RailButton(title: "Grid", symbol: "grid", isOn: model.designGrid != .off) { model.designGrid = Self.nextGrid(after: model.designGrid) }
        separator
        RailButton(title: "Logcat", symbol: "text.alignleft") { openLogcat() }
        RailButton(title: "Statistics", symbol: "chart.xyaxis.line", isOn: model.showsStats) { model.showsStats.toggle() }
        separator
        captureButtons
        separator
        navigationButtons
    }

    // MARK: Shared groups

    @ViewBuilder
    private var navigationButtons: some View {
        RailButton(title: "Back", symbol: "chevron.backward") { model.press(.back) }
        RailButton(title: "Home", symbol: "circle") { model.press(.home) }
        RailButton(title: "Recents", symbol: "square") { model.press(.appSwitch) }
    }

    @ViewBuilder
    private var captureButtons: some View {
        RailButton(title: "Screenshot", symbol: "camera") { model.takeScreenshot() }
        RailButton(title: model.isRecording ? "Stop Recording" : "Record", symbol: model.isRecording ? "stop.fill" : "record.circle",
                   isOn: model.isRecording, tint: model.isRecording ? .white : nil) { model.toggleRecording() }
            .background(model.isRecording ? Theme.Palette.redFill.color : .clear, in: Capsule())
        RailButton(title: model.isMuted ? "Unmute" : "Mute", symbol: model.isMuted ? "speaker.slash" : "speaker.wave.2",
                   isOn: model.isMuted) { model.toggleMute() }
    }

    /// Off → 4 dp → 8 dp → off.
    static func nextGrid(after grid: DesignGrid) -> DesignGrid {
        switch grid {
        case .off: return .dp4
        case .dp4: return .dp8
        case .dp8: return .off
        }
    }

    /// A short line between groups of buttons: 24 wide, 4 pt above and below.
    private var separator: some View {
        Rectangle().fill(Self.divider).frame(width: 24, height: 1).padding(.vertical, Theme.Space.s1)
    }

    /// Hidden: a tab that brings it back (also in the window toolbar and in View ▸ Show Control Rail). A red dot stays while recording.
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
