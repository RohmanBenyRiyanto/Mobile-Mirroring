import Components
import DomainModels
import SwiftUI
import Theme

// MARK: Model

@MainActor
public final class DeveloperToolsModel: ObservableObject {
    @Published public private(set) var state = DeveloperState()
    @Published public private(set) var isLoaded = false
    @Published public private(set) var canUndo = false
    @Published public private(set) var failure: String?
    public let allowsNetworkSwitches: Bool
    @Published public private(set) var mockLocation: MockLocation?
    private var mockTask: Task<Void, Never>?

    private var baseline: DeveloperState?
    private var beforeLastChange: DeveloperState?
    private let run: @Sendable (String) throws -> String
    public var confirmNetworkOff: (() -> Bool)?
    public var onOwed: ((_ baseline: DeveloperState) -> Void)?
    public var onSettled: (() -> Void)?
    public var onMockChanged: ((_ active: Bool) -> Void)?

    public init(allowsNetworkSwitches: Bool = true, run: @escaping @Sendable (String) throws -> String) {
        self.allowsNetworkSwitches = allowsNetworkSwitches
        self.run = run
    }

    public var hasChanges: Bool { mockLocation != nil || (baseline.map { $0 != state } ?? false) }

    public func load() async {
        let run = self.run
        guard let output = await Task.detached(operation: { try? run(DeveloperSettings.readCommand) }).value else {
            failure = String(localized: "The phone did not answer")
            return
        }
        failure = nil
        isLoaded = true
        state = DeveloperSettings.parse(output)
        if baseline == nil { baseline = state }
    }

    public func change(_ edit: (inout DeveloperState) -> Void) {
        var new = state
        edit(&new)
        if (state.wifiOn && !new.wifiOn) || (state.mobileDataOn && !new.mobileDataOn), confirmNetworkOff?() == false {
            objectWillChange.send()
            return
        }
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
        stopMocking()
        guard let baseline else { return }
        beforeLastChange = nil
        canUndo = false
        apply(baseline)
    }

    public func restoreOnEnd() {
        mockTask?.cancel()
        if mockLocation != nil { _ = try? run(MockLocation.stopCommand); mockLocation = nil; onMockChanged?(false) }
        guard let baseline, baseline != state else { return }
        let commands = DeveloperSettings.commands(from: state, to: baseline)
        let run = self.run
        _ = try? run(commands.joined(separator: "; "))
        state = baseline
        onSettled?()
    }

    public func startMocking(_ location: MockLocation) {
        let run = self.run
        onMockChanged?(true)
        do {
            _ = try run(location.startCommand)
        } catch {
            failure = String(localized: "The phone did not accept the change")
            return
        }
        failure = nil
        mockLocation = location
        mockTask?.cancel()
        mockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, let current = mockLocation, !Task.isCancelled else { return }
                _ = await Task.detached { try? run(current.updateCommand) }.value
            }
        }
    }

    public func stopMocking() {
        mockTask?.cancel()
        mockTask = nil
        guard mockLocation != nil else { return }
        _ = try? run(MockLocation.stopCommand)
        mockLocation = nil
        onMockChanged?(false)
    }

    private func apply(_ new: DeveloperState) {
        let commands = DeveloperSettings.commands(from: state, to: new)
        guard !commands.isEmpty else { return }
        let run = self.run
        if let baseline { onOwed?(baseline) }
        do {
            _ = try run(commands.joined(separator: "; "))
            failure = nil
            state = new
            if new == baseline { onSettled?() }
        } catch {
            failure = String(localized: "The phone did not accept the change")
        }
    }
}

// MARK: Panel

struct QuickTogglesPanel: View {
    static let width: CGFloat = 300
    @ObservedObject var tools: DeveloperToolsModel
    @ObservedObject var traffic: TrafficModel
    @State private var coordinates = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            if !tools.isLoaded && tools.failure == nil { LoadingLabel("Reading the phone").padding(Theme.Space.s3).frame(maxWidth: .infinity, alignment: .leading) }
            GroupedForm {
                Section {
                    Toggle("Layout bounds", isOn: binding(\.layoutBounds))
                    Toggle("GPU overdraw", isOn: binding(\.gpuOverdraw))
                    Toggle("Don’t keep activities", isOn: binding(\.dontKeepActivities))
                } header: { Text("Debugging") } footer: {
                    Text("Layout bounds and overdraw apply to apps the next time they open.")
                }
                Section {
                    Toggle("Do not disturb", isOn: binding(\.doNotDisturb))
                } header: { Text("Game focus") } footer: {
                    Text("Silences calls and banners while you play. Turned off again when you disconnect.")
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
                Section {
                    Picker("Place", selection: Binding(get: { tools.mockLocation }, set: { place in place.map(tools.startMocking) ?? tools.stopMocking() })) {
                        Text("Real location").tag(MockLocation?.none)
                        ForEach(MockLocation.presets, id: \.name) { Text(verbatim: $0.name).tag(MockLocation?.some($0.location)) }
                    }
                    LabeledContent("Coordinates") {
                        TextField("", text: $coordinates, prompt: Text(verbatim: "-6.2088, 106.8456"))
                            .textFieldStyle(.roundedBorder).font(Theme.Font.mono).multilineTextAlignment(.trailing)
                            .onSubmit { if let place = MockLocation(text: coordinates) { tools.startMocking(place) } }
                    }
                } header: { Text("Location") } footer: {
                    Text("Needs Android 12 or later. The real location returns when you pick Real location, press Reset All or disconnect.")
                }
                if tools.allowsNetworkSwitches {
                    Section {
                        Toggle("Wi-Fi", isOn: binding(\.wifiOn))
                        Toggle("Mobile data", isOn: binding(\.mobileDataOn))
                    } header: { Text("Network") } footer: { Text("Switch both off to test how the app behaves without a connection.") }
                }
                Section {
                    Toggle("Send traffic through this Mac", isOn: Binding(get: { traffic.isOn }, set: { $0 ? traffic.start() : traffic.stop() }))
                    Picker("Network speed", selection: $traffic.profile) {
                        ForEach(NetworkProfile.presets) { preset in Text(LocalizedStringKey(preset.title)).tag(preset) }
                    }
                    .disabled(!traffic.isOn)
                    Button("Open API Log") { openWindow(id: "apilog") }
                } header: { Text("Traffic") } footer: {
                    Text("The phone’s proxy setting returns to normal when you switch this off or disconnect. Network speed slows what goes through this Mac, so switch it on first. Apps that skip the proxy are not slowed.")
                }
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
        .animated(value: tools.isLoaded)
        .task { await tools.load() }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<DeveloperState, Value>) -> Binding<Value> {
        Binding(get: { tools.state[keyPath: keyPath] }, set: { value in tools.change { $0[keyPath: keyPath] = value } })
    }
}
