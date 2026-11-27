import Components
import SwiftUI
import Theme
import WorkspaceFeature

/// Disconnect and the hide button are always on the rail, so it can never be made unusable.
struct RailTab: View {
    @ObservedObject var model: AppModel
    @State private var mode: WorkspaceMode

    init(model: AppModel) {
        self.model = model
        _mode = State(initialValue: model.mode)
    }

    private var items: [RailItemID] { model.railLayout.items(for: mode) }

    var body: some View {
        SettingsCard(footer: "Each mode keeps its own list. Disconnect and the hide button are always on the rail.") {
            Picker("Mode", selection: $mode) {
                ForEach(WorkspaceMode.allCases) { mode in
                    Label { Text(mode.title) } icon: { Image(systemName: mode.symbol) }.tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        SettingsCard("Shown") {
            if items.isEmpty {
                Text("Nothing is shown. Add tools below.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack(spacing: Theme.Space.s3) {
                    Image(systemName: item.symbol).frame(width: 22).foregroundStyle(Theme.Palette.accentText.color)
                    Text(item.title)
                    Spacer()
                    Button { withAnimation(Theme.Motion.snappy) { model.railLayout.move(item, by: -1, in: mode) } } label: { Image(systemName: "chevron.up") }
                        .disabled(item == items.first)
                        .help("Move Up").accessibilityLabel("Move Up")
                    Button { withAnimation(Theme.Motion.snappy) { model.railLayout.move(item, by: 1, in: mode) } } label: { Image(systemName: "chevron.down") }
                        .disabled(item == items.last)
                        .help("Move Down").accessibilityLabel("Move Down")
                    Button { withAnimation(Theme.Motion.snappy) { model.railLayout.remove(item, from: mode) } } label: { Image(systemName: "minus.circle") }
                        .help("Remove").accessibilityLabel("Remove")
                }
                .buttonStyle(.borderless)
            }
            .onMove { source, destination in model.railLayout.move(fromOffsets: source, toOffset: destination, in: mode) }
        }

        let hidden = model.railLayout.hidden(in: mode)
        if !hidden.isEmpty {
            SettingsCard("Available") {
                ForEach(hidden) { item in
                    HStack(spacing: Theme.Space.s3) {
                        Image(systemName: item.symbol).frame(width: 22).foregroundStyle(.secondary)
                        Text(item.title)
                        Spacer()
                        Button { withAnimation(Theme.Motion.snappy) { model.railLayout.add(item, to: mode) } } label: { Image(systemName: "plus.circle") }
                            .buttonStyle(.borderless)
                            .help("Add").accessibilityLabel("Add")
                    }
                }
            }
        }

        SettingsCard {
            Button("Reset This Mode") { withAnimation(Theme.Motion.snappy) { model.railLayout.reset(mode) } }
                .disabled(items == RailLayout.defaultItems(for: mode))
            Button("Reset All Modes") { withAnimation(Theme.Motion.snappy) { model.railLayout = .standard } }
                .disabled(model.railLayout.isStandard)
        }
    }
}
