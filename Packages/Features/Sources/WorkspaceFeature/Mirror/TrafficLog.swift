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
                log.finish(id: report.id, status: report.status, durationMillis: duration, sent: report.sent, received: report.received, details: report.details)
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
    @State private var selection: Int?
    @State private var section = Section.overview

    enum Section: String, CaseIterable, Identifiable {
        case overview, request, response
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .overview ? "Overview" : (self == .request ? "Request" : "Response") }
    }

    private var selected: APICall? { traffic.log.calls.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Send traffic through this Mac", isOn: Binding(get: { traffic.isOn }, set: { $0 ? traffic.start() : traffic.stop() })).toggleStyle(.switch)
                Spacer()
                Button("Copy CSV") { traffic.copyCSV() }.disabled(traffic.log.calls.isEmpty)
                Button("Clear") { selection = nil; traffic.clear() }.disabled(traffic.log.calls.isEmpty)
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
                VSplitView {
                    Table(traffic.log.calls.reversed(), selection: $selection) {
                        TableColumn("Method") { Text(verbatim: $0.isTunnel ? "HTTPS" : $0.method).font(Theme.Font.mono) }.width(60)
                        TableColumn("Address") { Text(verbatim: $0.url).font(Theme.Font.mono).lineLimit(1).truncationMode(.middle) }
                        TableColumn("Status") { call in
                            Text(verbatim: call.status.map(String.init) ?? "–").font(Theme.Font.mono).foregroundStyle(call.isError ? Theme.Palette.red.color : .primary)
                        }.width(56)
                        TableColumn("Time") { Text(verbatim: $0.durationMillis.map { "\($0) ms" } ?? "…").font(Theme.Font.mono) }.width(72)
                        TableColumn("Size") { call in
                            Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(call.sentBytes + call.receivedBytes), countStyle: .file)).font(Theme.Font.mono)
                        }.width(72)
                    }
                    .frame(minHeight: 140)
                    detail.frame(minHeight: 160)
                }
            }
            Divider()
            Text("HTTPS calls show only the address. Their contents stay encrypted.").font(Theme.Font.caption).foregroundStyle(.secondary).padding(Theme.Space.s2)
        }
        .frame(minWidth: 720, minHeight: 440)
    }

    // MARK: Detail pane

    @ViewBuilder private var detail: some View {
        if let call = selected {
            VStack(spacing: 0) {
                HStack {
                    Picker("Section", selection: $section) { ForEach(Section.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                    Spacer()
                    if let details = call.details {
                        Button("Copy as cURL") { copy(HTTPMessage.curl(method: call.method, url: call.url, headers: details.requestHeaders, body: details.requestBody)) }
                    }
                }
                .padding(Theme.Space.s3)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s3) { content(for: call) }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Theme.Space.s3)
                }
            }
        } else {
            Text("Select a call to see its request and response.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func content(for call: APICall) -> some View {
        if call.isTunnel {
            Label("This is an HTTPS connection. Its contents are encrypted between the app and the server, so only the address and size are known.", systemImage: "lock.fill")
                .foregroundStyle(.secondary)
            overview(call)
        } else if let details = call.details {
            switch section {
            case .overview: overview(call); headerList("Request headers", details.requestHeaders)
            case .request: headerList("Headers", details.requestHeaders); bodyView(details.requestBody, headers: details.requestHeaders, truncated: details.requestBodyTruncated)
            case .response:
                Text(verbatim: details.statusLine).font(Theme.Font.mono)
                headerList("Headers", details.responseHeaders); bodyView(details.responseBody, headers: details.responseHeaders, truncated: details.responseBodyTruncated)
            }
        } else {
            LoadingLabel("Waiting for the response")
        }
    }

    private func overview(_ call: APICall) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            row("URL", call.url)
            row("Method", call.isTunnel ? "CONNECT" : call.method)
            row("Status", call.details?.statusLine ?? call.status.map(String.init) ?? "–")
            row("Time", call.durationMillis.map { "\($0) ms" } ?? "…")
            row("Sent", ByteCountFormatter.string(fromByteCount: Int64(call.sentBytes), countStyle: .file))
            row("Received", ByteCountFormatter.string(fromByteCount: Int64(call.receivedBytes), countStyle: .file))
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s3) {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(verbatim: value).font(Theme.Font.mono).textSelection(.enabled)
        }
    }

    private func headerList(_ title: LocalizedStringKey, _ headers: [HTTPHeader]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            HStack {
                Text(title).font(Theme.Font.emphasized)
                Spacer()
                Button("Copy") { copy(headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")) }.buttonStyle(.link).disabled(headers.isEmpty)
            }
            if headers.isEmpty { Text("None").foregroundStyle(.secondary) }
            ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s3) {
                    Text(verbatim: header.name).font(Theme.Font.monoCaption).foregroundStyle(.secondary).frame(width: 170, alignment: .leading)
                    Text(verbatim: header.value).font(Theme.Font.monoCaption).textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder private func bodyView(_ body: Data, headers: [HTTPHeader], truncated: Bool) -> some View {
        let preview = HTTPMessage.preview(of: body, headers: headers, truncated: truncated)
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            HStack {
                Text("Body").font(Theme.Font.emphasized)
                Spacer()
                if case let .text(text, _) = preview { Button("Copy") { copy(text) }.buttonStyle(.link) }
            }
            switch preview {
            case .empty: Text("No body").foregroundStyle(.secondary)
            case let .text(text, cut):
                Text(verbatim: text).font(Theme.Font.monoCaption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                if cut { Text("Only the first 64 KB are kept.").font(Theme.Font.caption).foregroundStyle(.secondary) }
            case let .binary(bytes, type):
                let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                let kind = type.map { " · " + $0 } ?? ""
                Text("Binary data, \(size)\(kind)").foregroundStyle(.secondary)
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
