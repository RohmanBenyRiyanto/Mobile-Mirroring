import Components
import DomainModels
import SwiftUI
import Theme

// MARK: Model

/// Reads and changes the phone's developer switches. Whatever was changed is put back by Reset All and when the phone is disconnected.
@MainActor
public final class DeveloperToolsModel: ObservableObject {
    @Published public private(set) var state = DeveloperState()
    @Published public private(set) var canUndo = false
    @Published public private(set) var failure: String?

    private var baseline: DeveloperState?
    private var beforeLastChange: DeveloperState?
    private let run: @Sendable (String) throws -> String

    public init(run: @escaping @Sendable (String) throws -> String) { self.run = run }

    public var hasChanges: Bool { baseline.map { $0 != state } ?? false }

    public func load() async {
        let run = self.run
        guard let output = await Task.detached(operation: { try? run(DeveloperSettings.readCommand) }).value else {
            failure = String(localized: "The phone did not answer")
            return
        }
        failure = nil
        state = DeveloperSettings.parse(output)
        if baseline == nil { baseline = state }
    }

    public func change(_ edit: (inout DeveloperState) -> Void) {
        var new = state
        edit(&new)
        beforeLastChange = state
        apply(new)
        canUndo = beforeLastChange != nil
    }

    public func undo() {
        guard let previous = beforeLastChange else { return }
        beforeLastChange = nil
        canUndo = false
        apply(previous)
    }

    public func resetAll() {
        guard let baseline else { return }
        beforeLastChange = nil
        canUndo = false
        apply(baseline)
    }

    /// Called when the session ends. Best effort: if the cable is already gone nothing can be sent.
    public func restoreOnEnd() {
        guard let baseline, baseline != state else { return }
        let commands = DeveloperSettings.commands(from: state, to: baseline)
        let run = self.run
        _ = try? run(commands.joined(separator: "; "))
        state = baseline
    }

    private func apply(_ new: DeveloperState) {
        let commands = DeveloperSettings.commands(from: state, to: new)
        guard !commands.isEmpty else { return }
        let run = self.run
        do {
            _ = try run(commands.joined(separator: "; "))
            failure = nil
            state = new
        } catch {
            failure = String(localized: "The phone did not accept the change")
        }
    }
}

// MARK: Panel

struct QuickTogglesPanel: View {
    static let width: CGFloat = 300
    @ObservedObject var tools: DeveloperToolsModel

    var body: some View {
        VStack(spacing: 0) {
            GroupedForm {
                Section {
                    Toggle("Layout bounds", isOn: binding(\.layoutBounds))
                    Toggle("GPU overdraw", isOn: binding(\.gpuOverdraw))
                    Toggle("Don’t keep activities", isOn: binding(\.dontKeepActivities))
                } header: { Text("Debugging") } footer: {
                    Text("Layout bounds and overdraw apply to apps the next time they open.")
                }
                Section {
                    Picker("Animation speed", selection: binding(\.animationScale)) {
                        ForEach(DeveloperState.animationScales, id: \.self) { scale in
                            Text(scale == 0 ? String(localized: "Off") : "\(scale.formatted())×").tag(scale)
                        }
                    }
                    Picker("Dark mode", selection: binding(\.nightMode)) {
                        Text("Automatic").tag(DeveloperState.NightMode.auto)
                        Text("On").tag(DeveloperState.NightMode.yes)
                        Text("Off").tag(DeveloperState.NightMode.no)
                    }
                } header: { Text("Display") }
                if let failure = tools.failure {
                    Section { Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
            }
            HStack {
                Button("Undo") { tools.undo() }.secondaryAction().disabled(!tools.canUndo)
                Button("Reset All") { tools.resetAll() }.secondaryAction().disabled(!tools.hasChanges)
                Spacer()
            }
            .padding(Theme.Space.s3)
        }
        .frame(width: Self.width)
        .task { await tools.load() }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<DeveloperState, Value>) -> Binding<Value> {
        Binding(get: { tools.state[keyPath: keyPath] }, set: { value in tools.change { $0[keyPath: keyPath] = value } })
    }
}
