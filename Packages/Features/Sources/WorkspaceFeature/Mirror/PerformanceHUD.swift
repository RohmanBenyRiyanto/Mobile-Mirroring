import AppKit
import Components
import DomainModels
import SwiftUI
import Theme

// MARK: Monitor

/// Samples the phone once a second while the HUD is on screen. Nothing runs when it is hidden.
@MainActor
public final class PerformanceMonitor: ObservableObject {
    @Published public private(set) var latest: PerformanceSample?
    @Published public private(set) var history = PerformanceHistory()
    @Published public private(set) var package: String?

    private var task: Task<Void, Never>?
    private var previous: (reading: PerformanceReading, at: ContinuousClock.Instant)?

    public init() {}

    public func start(package: @escaping @MainActor () -> String?, fetch: @escaping @Sendable (String) throws -> String) {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let self, let name = package() {
                    let output = await Task.detached { try? fetch(name) }.value
                    if Task.isCancelled { return }
                    if let output { self.ingest(PerformanceProbe.parse(output), package: name) }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        previous = nil
    }

    public func reset() {
        history.reset()
        latest = nil
        previous = nil
    }

    func ingest(_ reading: PerformanceReading, package name: String, now: ContinuousClock.Instant = .now) {
        // A different app has different counters, so the comparison and the history start over.
        if name != package { reset(); package = name }
        if let previous {
            let seconds = Double((now - previous.at).components.seconds) + Double((now - previous.at).components.attoseconds) / 1e18
            let sample = PerformanceSample.between(previous.reading, reading, seconds: seconds)
            latest = sample
            history.append(sample)
        }
        previous = (reading, now)
    }

    public func copyCSV() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(history.csv(), forType: .string)
    }
}

// MARK: Panel

struct PerformancePanel: View {
    static let width: CGFloat = 300
    @EnvironmentObject private var model: AppModel
    @ObservedObject var monitor: PerformanceMonitor

    var body: some View {
        VStack(spacing: 0) {
            GroupedForm {
                Section {
                    PlainRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Performance").font(Theme.Font.headline)
                            Text(monitor.package ?? String(localized: "Waiting for an app")).font(Theme.Font.monoCaption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                if !warnings.isEmpty {
                    Section {
                        ForEach(warnings, id: \.self) { warning in
                            Label { Text(Self.message(for: warning)) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        }
                    }
                }
                Section {
                    metric("Frame rate", value: monitor.latest?.framesPerSecond.map { String(format: "%.0f fps", $0) }, series: monitor.history.samples.map { $0.framesPerSecond }, ceiling: 120)
                    metric("Janky frames", value: monitor.latest?.jankPercent.map { String(format: "%.0f%%", $0) }, series: monitor.history.samples.map { $0.jankPercent }, ceiling: 100)
                    metric("App CPU", value: monitor.latest?.appCPUPercent.map { String(format: "%.0f%%", $0) }, series: monitor.history.samples.map { $0.appCPUPercent }, ceiling: 100)
                    metric("Phone CPU", value: monitor.latest.map { String(format: "%.0f%%", $0.systemCPUPercent) }, series: monitor.history.samples.map { $0.systemCPUPercent }, ceiling: 100)
                    LabeledContent("App memory") { number(monitor.latest?.appMemoryMB.map { String(format: "%.0f MB", $0) }) }
                    LabeledContent("Memory in use") { number(monitor.latest?.memoryUsedPercent.map { String(format: "%.0f%%", $0) }) }
                    LabeledContent("Battery temperature") { number(monitor.latest?.temperatureCelsius.map { String(format: "%.1f °C", $0) }) }
                } footer: {
                    Text("Frame rate and jank come from the app in front. Games that draw on their own may show none.")
                }
            }
            HStack {
                Button("Copy CSV") { monitor.copyCSV() }.secondaryAction().disabled(monitor.history.samples.isEmpty)
                Button("Reset") { monitor.reset() }.secondaryAction()
                Spacer()
            }
            .padding(Theme.Space.s3)
        }
        .frame(width: Self.width)
        .onAppear { model.startPerformanceMonitoring() }
        .onDisappear { monitor.stop() }
    }

    private var warnings: [PerformanceWarning] { monitor.latest.map(PerformanceWarning.warnings(for:)) ?? [] }

    private func metric(_ title: LocalizedStringKey, value: String?, series: [Double?], ceiling: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            LabeledContent(title) { number(value) }
            Sparkline(values: series, ceiling: ceiling).frame(height: 22)
        }
    }

    private func number(_ text: String?) -> some View {
        LoadedValue(isLoading: text == nil && monitor.latest == nil, skeletonWidth: 56) {
            numberText(text)
        }
    }

    private func numberText(_ text: String?) -> some View {
        Text(verbatim: text ?? "–").font(Theme.Font.mono).foregroundStyle(text == nil ? .secondary : .primary).monospacedDigit()
    }

    private static func message(for warning: PerformanceWarning) -> LocalizedStringKey {
        switch warning {
        case .hot: "The phone is getting hot"
        case .lowMemory: "The phone is almost out of memory"
        case .jank: "Many frames are being dropped"
        case .busyCPU: "The processor is fully busy"
        }
    }
}

private struct Sparkline: View {
    let values: [Double?]
    let ceiling: Double

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let step = proxy.size.width / CGFloat(max(PerformanceHistory.capacity - 1, 1))
                let offset = CGFloat(PerformanceHistory.capacity - values.count) * step
                var open = false
                for (index, value) in values.enumerated() {
                    guard let value else { open = false; continue }
                    let point = CGPoint(x: offset + CGFloat(index) * step, y: proxy.size.height * (1 - CGFloat(min(value, ceiling) / ceiling)))
                    if open { path.addLine(to: point) } else { path.move(to: point); open = true }
                }
            }
            .stroke(Theme.Palette.accentText.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
