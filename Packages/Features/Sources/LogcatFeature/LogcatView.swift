import AppKit
import SwiftUI
import DomainModels
import Networking

/// What the logcat window needs from its host: the phone, how to reach it, and the app in front, re-read on change.
@MainActor
public protocol LogcatSource: ObservableObject {
    var adb: ADB? { get }
    var targetSerial: String? { get }
    var frontPackage: String? { get }
}

public struct LogcatView<Source: LogcatSource>: View {
    @ObservedObject public var source: Source

    @StateObject private var logcat = LogcatModel()
    @State private var jumpTarget: Int?
    @FocusState private var filterIsFocused: Bool

    public init(source: Source) {
        self.source = source
    }

    private var frontPackage: String? { source.frontPackage }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            LogList(entries: logcat.visibleEntries, followsTail: !logcat.isPaused, package: logcat.scope == .foregroundApp ? logcat.foregroundPackage : nil,
                    jumpTarget: $jumpTarget)
        }
        .frame(minWidth: 720, minHeight: 360)
        .task(id: source.targetSerial) {
            restart()
            logcat.setForegroundPackage(frontPackage)
        }
        .onChange(of: frontPackage) { _, package in logcat.setForegroundPackage(package) }
        .onDisappear { logcat.stop() }
        .focusedSceneValue(\.logcatActions, LogcatActions(isPaused: logcat.isPaused, togglePause: { logcat.isPaused.toggle() },
                                                         clear: { logcat.clear() }, focusFilter: { filterIsFocused = true }))
    }

    private var toolbar: some View {
        HStack {
            Picker("Show", selection: $logcat.scope) {
                ForEach(LogcatModel.Scope.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 190)
            if logcat.scope == .foregroundApp {
                Text(logcat.foregroundPackage ?? "waiting for an app…")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Picker("Level", selection: $logcat.minimumLevel) {
                ForEach(LogLevel.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 140)
            TextField("Filter", text: $logcat.filter)
                .focused($filterIsFocused)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)
            Button { jumpTarget = logcat.crashIDs.last } label: {
                Label("\(logcat.crashIDs.count)", systemImage: "exclamationmark.octagon")
            }
            .disabled(logcat.crashIDs.isEmpty)
            .help("Jump to the last crash (\(logcat.crashIDs.count) so far)")
            Toggle("Pause", isOn: $logcat.isPaused)
            Button("Clear") { logcat.clear() }
            Button("Copy") { copyVisible() }
            Button(logcat.isRunning ? "Restart" : "Start") { restart() }
        }
        .padding(8)
    }

    private func restart() {
        guard let adb = source.adb, let serial = source.targetSerial else { return }
        logcat.start(adb: adb, serial: serial)
    }

    private func copyVisible() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logcat.visibleEntries.map(\.text).joined(separator: "\n"), forType: .string)
    }
}

public struct LogList: View {
    public let entries: [LogEntry]
    public let followsTail: Bool
    public let package: String?
    @Binding public var jumpTarget: Int?

    public init(entries: [LogEntry], followsTail: Bool, package: String?, jumpTarget: Binding<Int?>) {
        self.entries = entries
        self.followsTail = followsTail
        self.package = package
        self._jumpTarget = jumpTarget
    }

    public var body: some View {
        ScrollViewReader { proxy in
            List(entries) { entry in
                LogRow(entry: entry, package: package)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 8))
            }
            .listStyle(.plain)
            .onChange(of: entries.last?.id) { _, last in
                if followsTail, let last { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: .top)
                jumpTarget = nil
            }
        }
    }
}

public struct LogRow: View {
    public let entry: LogEntry
    public let package: String?

    public init(entry: LogEntry, package: String?) {
        self.entry = entry
        self.package = package
    }

    public var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(entry.crashBlock == nil ? Color.clear : Color.red.opacity(0.7)).frame(width: 3)
            Text(entry.text)
                .font(.system(size: 11, weight: weight, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, entry.kind.startsCrash ? 3 : 0)
        .background(entry.kind.startsCrash ? Color.red.opacity(0.18) : Color.clear)
    }

    private var isOwnFrame: Bool {
        entry.kind == .stackFrame && package.map { entry.message.contains($0) } == true
    }

    private var weight: Font.Weight {
        switch entry.kind {
        case .crash, .nativeCrash, .anr, .exception, .processDied: return .bold
        case .causedBy: return .semibold
        case .stackFrame: return isOwnFrame ? .semibold : .regular
        case .normal: return .regular
        }
    }

    private var color: Color {
        switch entry.kind {
        case .crash, .nativeCrash, .anr, .exception: return .red
        case .causedBy, .processDied: return .orange
        case .stackFrame: return isOwnFrame ? .primary : .secondary
        case .normal:
            switch entry.level {
            case .verbose, .debug: return .secondary
            case .info: return .primary
            case .warning: return .orange
            case .error, .fatal: return .red
            }
        }
    }
}
