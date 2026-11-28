import AppKit
import Components
import DomainModels
import Networking
import SwiftUI
import Theme
import UniformTypeIdentifiers

// MARK: Model

/// Sends the phone's traffic through a logging proxy on this Mac. The phone's own proxy setting is put back when it stops.
@MainActor
public final class TrafficModel: ObservableObject {
    @Published public private(set) var log = APICallLog()
    @Published public private(set) var isOn = false
    @Published public private(set) var failure: String?

    private let run: @Sendable ([String]) throws -> String
    private var proxy: LoggingProxy?
    private var originalSetting: String?
    private let buffer = LockedValue<[LoggingProxy.Report]>([])
    private var flushTask: Task<Void, Never>?

    /// `run` executes adb arguments for this phone (the serial is already included).
    public init(run: @escaping @Sendable ([String]) throws -> String) { self.run = run }

    public func start() {
        guard !isOn else { return }
        let buffer = self.buffer
        do {
            let proxy = try LoggingProxy { report in buffer.withLock { $0.append(report) } }
            let port = Int(proxy.port)
            let original = try run(["shell", "settings get global http_proxy"]).trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try run(["reverse", "tcp:\(port)", "tcp:\(port)"])
            do { _ = try run(["shell", "settings put global http_proxy 127.0.0.1:\(port)"]) } catch {
                _ = try? run(["reverse", "--remove", "tcp:\(port)"])
                throw error
            }
            proxy.start()
            self.proxy = proxy
            originalSetting = original
            isOn = true
            failure = nil
            flushTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    self?.flush()
                }
            }
        } catch {
            failure = String(localized: "The phone did not accept the change")
        }
    }

    public func stop() {
        guard isOn, let proxy else { return }
        flushTask?.cancel()
        flushTask = nil
        let original = originalSetting ?? ""
        let restore = original.isEmpty || original == "null" || original == ":0" ? ":0" : original
        _ = try? run(["shell", "settings put global http_proxy \(restore)"])
        if restore == ":0" { _ = try? run(["shell", "settings delete global http_proxy"]) }
        _ = try? run(["reverse", "--remove", "tcp:\(proxy.port)"])
        proxy.stop()
        self.proxy = nil
        isOn = false
        flush()
    }

    public func clear() { log.clear() }

    public func copyCSV() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log.csv(), forType: .string)
    }

    func flush() {
        let reports = buffer.withLock { all -> [LoggingProxy.Report] in defer { all.removeAll() }; return all }
        for report in reports {
            if let duration = report.durationMillis {
                log.finish(id: report.id, status: report.status, durationMillis: duration, sent: report.sent, received: report.received)
            } else {
                log.begin(APICall(id: report.id, startedAt: report.startedAt, method: report.request.method, host: report.request.host,
                                  url: report.request.url, isTunnel: report.request.isTunnel))
            }
        }
    }
}

// MARK: Window

public struct TrafficLogView: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    public var body: some View {
        if let session = model.active {
            TrafficTable(traffic: session.traffic)
        } else {
            VStack { Text("Connect a phone to see its network calls.").foregroundStyle(.secondary) }
                .frame(minWidth: 640, minHeight: 320)
        }
    }
}

private struct TrafficTable: View {
    @ObservedObject var traffic: TrafficModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Send traffic through this Mac", isOn: Binding(get: { traffic.isOn }, set: { $0 ? traffic.start() : traffic.stop() })).toggleStyle(.switch)
                Spacer()
                Button("Copy CSV") { traffic.copyCSV() }.disabled(traffic.log.calls.isEmpty)
                Button("Clear") { traffic.clear() }.disabled(traffic.log.calls.isEmpty)
            }
            .padding(Theme.Space.s3)
            Divider()
            if let failure = traffic.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).padding(Theme.Space.s3)
                Divider()
            }
            if traffic.log.calls.isEmpty {
                VStack(spacing: Theme.Space.s2) {
                    Image(systemName: "network").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(traffic.isOn ? "Waiting for the phone to make a call" : "No calls yet").font(Theme.Font.headline)
                    Text(traffic.isOn ? "Use an app on the phone and its requests appear here." : "Turn on “Send traffic through this Mac” to see the phone’s requests.").foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            Table(traffic.log.calls.reversed()) {
                TableColumn("Method") { Text(verbatim: $0.isTunnel ? "HTTPS" : $0.method).font(Theme.Font.mono) }.width(60)
                TableColumn("Address") { Text(verbatim: $0.url).font(Theme.Font.mono).lineLimit(1).truncationMode(.middle) }
                TableColumn("Status") { call in
                    Text(verbatim: call.status.map(String.init) ?? "–").font(Theme.Font.mono).foregroundStyle(call.isError ? Theme.Palette.red.color : .primary)
                }.width(56)
                TableColumn("Time") { Text(verbatim: $0.durationMillis.map { "\($0) ms" } ?? "").font(Theme.Font.mono) }.width(72)
                TableColumn("Size") { call in
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(call.sentBytes + call.receivedBytes), countStyle: .file)).font(Theme.Font.mono)
                }.width(72)
            }
            }
            Divider()
            Text("HTTPS calls show only the address. Their contents stay encrypted.").font(Theme.Font.caption).foregroundStyle(.secondary).padding(Theme.Space.s2)
        }
        .frame(minWidth: 720, minHeight: 360)
    }
}
