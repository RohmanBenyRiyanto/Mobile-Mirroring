import AppKit
import SwiftUI
import DomainModels
import Networking
import Theme

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
            LogHeader()
            Divider()
            LogList(entries: logcat.visibleEntries, followsTail: !logcat.isPaused, package: logcat.scope == .foregroundApp ? logcat.foregroundPackage : nil,
                    jumpTarget: $jumpTarget)
            Divider()
            statusLine
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
            Button(logcat.isPaused ? "Resume" : "Pause") { logcat.isPaused.toggle() }
            Button("Clear") { logcat.clear() }
            Button("Copy") { copyVisible() }
            Button(logcat.isRunning ? "Restart" : "Start") { restart() }
        }
        .padding(8)
    }

    private var statusLine: some View {
        HStack(spacing: Theme.Space.s3) {
            Text("\(logcat.visibleEntries.count) lines")
            if !logcat.crashIDs.isEmpty { Text("\(logcat.crashIDs.count) crashes").foregroundStyle(Theme.Palette.red.color) }
            Spacer()
            Text(logcat.isPaused ? "Paused" : (logcat.isRunning ? "Following" : "Stopped"))
        }
        .font(Theme.Font.caption).foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Space.s3).padding(.vertical, Theme.Space.s2)
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

struct LogHeader: View {
    var body: some View {
        HStack(spacing: Theme.Space.s2) {
            Text("Time").frame(width: LogColumns.time, alignment: .leading)
            Text("PID").frame(width: LogColumns.pid, alignment: .trailing)
            Text("L").frame(width: LogColumns.level)
            Text("Tag").frame(width: LogColumns.tag, alignment: .leading)
            Text("Message").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Theme.Font.caption.weight(.medium)).foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Space.s3).padding(.vertical, 4)
    }
}

enum LogColumns {
    static let time: CGFloat = 92
    static let pid: CGFloat = 48
    static let level: CGFloat = 18
    static let tag: CGFloat = 140
}

public struct LogRow: View {
    public let entry: LogEntry
    public let package: String?

    public init(entry: LogEntry, package: String?) {
        self.entry = entry
        self.package = package
    }

    public var body: some View {
        HStack(spacing: Theme.Space.s2) {
            Rectangle().fill(entry.crashBlock == nil ? Color.clear : Color.red.opacity(0.7)).frame(width: 3)
            if entry.pid != nil && entry.kind == .normal {
                Text(verbatim: entry.time).foregroundStyle(.secondary).frame(width: LogColumns.time, alignment: .leading)
                Text(verbatim: entry.pid.map(String.init) ?? "").foregroundStyle(.secondary).frame(width: LogColumns.pid, alignment: .trailing)
                Text(verbatim: String(entry.level.letter))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(color)
                    .frame(width: LogColumns.level, height: 16)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                Text(verbatim: entry.tag).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).frame(width: LogColumns.tag, alignment: .leading)
                Text(verbatim: entry.message).foregroundStyle(color).textSelection(.enabled)
            } else {
                Text(verbatim: entry.text).fontWeight(weight).foregroundStyle(color).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced).monospacedDigit())
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
