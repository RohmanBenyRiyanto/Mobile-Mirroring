import DomainModels
import Foundation
import GRPC
import Networking
import NIOCore
import NIOPosix
import SwiftProtobuf

public enum AppInspectorError: LocalizedError, Equatable {
    case studioNotFound
    case unsupportedPhone(String)
    case appNotRunning(String)
    case notDebuggable(String)
    case noAnswer(String)
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .studioNotFound:
            return String(localized: "Android Studio was not found. Looking inside an app uses the inspector that comes with Android Studio, so install it in Applications.")
        case let .unsupportedPhone(abi): return String(localized: "This phone's processor (\(abi)) is not supported.")
        case let .appNotRunning(name): return String(localized: "\(name) is not running. Open it on the phone first.")
        case let .notDebuggable(name): return String(localized: "\(name) is not a debug build, so it cannot be looked into. Only apps built as debuggable can.")
        case let .noAnswer(step): return String(localized: "The phone did not answer while \(step).")
        case let .rejected(message): return String(localized: "The app refused the inspector: \(message)")
        }
    }
}

public final class AppInspectorSession: @unchecked Sendable {
    public let package: String
    private let adb: ADB
    private let serial: String
    private let onCall: @Sendable (APICall) -> Void
    private let onEnded: @Sendable (String?) -> Void

    private let inspectorID = "studio.network.inspection"
    private let state = LockedValue(State())
    private var group: MultiThreadedEventLoopGroup?
    private var channel: GRPCChannel?
    private var client: Profiler_Proto_TransportServiceAsyncClient?
    private var readerTask: Task<Void, Never>?
    private var forwardPort: String?
    private var ownsDaemon = false
    private var pid: Int32 = 0

    private struct State {
        var waiting: [UInt32: CheckedContinuation<Profiler_Proto_AppInspectionResponse, Error>] = [:]
        var agent: CheckedContinuation<Profiler_Proto_AgentData.Status, Never>?
        var agentStatus: Profiler_Proto_AgentData.Status?
        var chunks: [Int64: [UInt32: Data]] = [:]
        var chunkCounts: [Int64: UInt32] = [:]
        var assembler = InspectionAssembler()
        var nextCommand: UInt32 = 100
        var stopped = false
    }

    public init(adb: ADB, serial: String, package: String, onCall: @escaping @Sendable (APICall) -> Void, onEnded: @escaping @Sendable (String?) -> Void) {
        self.adb = adb
        self.serial = serial
        self.package = package
        self.onCall = onCall
        self.onEnded = onEnded
    }

    // MARK: Start and stop

    public func start(opensApp: Bool = false) async throws {
        let abiText = try shell("getprop ro.product.cpu.abi")
        guard let abi = PhoneABI(abi: abiText) else { throw AppInspectorError.unsupportedPhone(abiText.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let files = InspectorFiles.locate(abi: abi) else { throw AppInspectorError.studioNotFound }
        func runningPID() throws -> Int32? {
            let text = try shell("pidof \(PhoneTransferQuote.quote(package)) || true").trimmingCharacters(in: .whitespacesAndNewlines)
            return Int32(text.split(separator: " ").first ?? "")
        }
        var found = try runningPID()
        if found == nil, opensApp {
            _ = try? shell("monkey -p \(PhoneTransferQuote.quote(package)) -c android.intent.category.LAUNCHER 1")
            for _ in 0..<20 where found == nil {
                try await Task.sleep(for: .milliseconds(500))
                found = try runningPID()
            }
        }
        guard let pid = found else { throw AppInspectorError.appNotRunning(package) }
        self.pid = pid

        try prepare(files: files, abi: abi)
        try startDaemon()
        try await connect()
        try await attachAgent(abi: abi)
        try await startInspector()
    }

    public func stop() async {
        let wasStopped = state.withLock { s -> Bool in let was = s.stopped; s.stopped = true; return was }
        if wasStopped { return }
        readerTask?.cancel()
        if client != nil {
            _ = try? await sendInspectorCommand(.disposeInspectorCommand(Profiler_Proto_DisposeInspectorCommand()), timeout: 2)
        }
        _ = try? await channel?.close().get()
        try? await group?.shutdownGracefully()
        if ownsDaemon { _ = try? shell("pkill -x transport; true") }
        if let forwardPort { _ = try? adb.run(["-s", serial, "forward", "--remove", "tcp:\(forwardPort)"], timeout: 5) }
        failPending(AppInspectorError.noAnswer(String(localized: "stopping")))
    }

    public func cleanUpPhoneNow() {
        if ownsDaemon { _ = try? shell("pkill -x transport; true", timeout: 5) }
        if let forwardPort { _ = try? adb.run(["-s", serial, "forward", "--remove", "tcp:\(forwardPort)"], timeout: 5) }
    }

    // MARK: Phone setup

    @discardableResult
    private func shell(_ command: String, timeout: TimeInterval = 20) throws -> String {
        String(decoding: try adb.run(["-s", serial, "shell", command], timeout: timeout), as: UTF8.self)
    }

    private func prepare(files: InspectorFiles, abi: PhoneABI) throws {
        _ = try shell("mkdir -p \(PhoneInspectorPaths.directory)")
        let uploads: [(URL, String, Bool)] = [
            (files.transport, PhoneInspectorPaths.transport, true),
            (files.agent, PhoneInspectorPaths.agentLibrary(for: abi), true),
            (files.perfa, PhoneInspectorPaths.perfa, false),
            (files.networkInspector, PhoneInspectorPaths.networkInspector, false),
        ]
        for (local, remote, executable) in uploads {
            let size = (try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            let there = Int((try? shell("stat -c %s \(PhoneTransferQuote.quote(remote)) 2>/dev/null || echo -1").trimmingCharacters(in: .whitespacesAndNewlines)) ?? "-1") ?? -1
            if there == size { continue }
            _ = try shell("rm -f \(PhoneTransferQuote.quote(remote))")
            _ = try adb.run(["-s", serial, "push", local.path, remote], timeout: 120)
            if executable { _ = try shell("chmod 755 \(PhoneTransferQuote.quote(remote))") }
        }
        for (data, remote) in [(InspectorConfig.daemon, PhoneInspectorPaths.daemonConfig), (InspectorConfig.agent, PhoneInspectorPaths.agentConfig)] {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("benzmirror-\(UUID().uuidString).config")
            try data.write(to: temporary)
            defer { try? FileManager.default.removeItem(at: temporary) }
            _ = try shell("rm -f \(remote)")
            _ = try adb.run(["-s", serial, "push", temporary.path, remote], timeout: 20)
            _ = try shell("chmod 644 \(remote)")
        }
    }

    private func startDaemon() throws {
        let running = try shell("pidof transport || true").trimmingCharacters(in: .whitespacesAndNewlines)
        if running.isEmpty {
            _ = try shell("cd \(PhoneInspectorPaths.directory) && (nohup ./transport -config_file=\(PhoneInspectorPaths.daemonConfig) >/dev/null 2>&1 &); sleep 1")
            ownsDaemon = true
        }
        let out = String(decoding: try adb.run(["-s", serial, "forward", "tcp:0", "localabstract:\(PhoneInspectorPaths.socketName)"], timeout: 10), as: UTF8.self)
        forwardPort = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let forwardPort, Int(forwardPort) != nil else { throw AppInspectorError.noAnswer(String(localized: "connecting to the phone")) }
    }

    // MARK: Connection

    private func connect() async throws {
        guard let forwardPort, let port = Int(forwardPort) else { return }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        let channel = try GRPCChannelPool.with(target: .host("127.0.0.1", port: port), transportSecurity: .plaintext, eventLoopGroup: group)
        self.channel = channel
        let client = Profiler_Proto_TransportServiceAsyncClient(channel: channel)
        self.client = client
        readerTask = Task { [weak self] in
            await self?.readEvents(client)
        }
    }

    private func execute(_ command: Profiler_Proto_Command, timeout: TimeInterval = 10) async throws {
        guard let client else { throw AppInspectorError.noAnswer(String(localized: "connecting")) }
        var request = Profiler_Proto_ExecuteRequest()
        request.command = command
        var lastError: Error?
        for _ in 0..<10 {
            do {
                _ = try await client.execute(request, callOptions: CallOptions(timeLimit: .timeout(.seconds(Int64(timeout)))))
                return
            } catch {
                lastError = error
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        throw lastError ?? AppInspectorError.noAnswer(String(localized: "connecting"))
    }

    private func attachAgent(abi: PhoneABI) async throws {
        var command = Profiler_Proto_Command()
        command.type = .beginSession
        command.pid = pid
        var begin = Profiler_Proto_BeginSession()
        begin.jvmtiConfig.attachAgent = true
        begin.jvmtiConfig.agentLibFileName = "libjvmtiagent_\(abi.agentSuffix).so"
        begin.jvmtiConfig.agentConfigPath = PhoneInspectorPaths.agentConfig
        begin.jvmtiConfig.packageName = package
        begin.sessionName = "Benz Mirror"
        begin.processAbi = abi.folder
        begin.requestTimeEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        command.beginSession = begin
        try await execute(command)

        let status = await withTaskGroup(of: Profiler_Proto_AgentData.Status?.self) { group in
            group.addTask { [self] in await waitForAgent() }
            group.addTask { try? await Task.sleep(for: .seconds(8)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if status == .unattachable { throw AppInspectorError.notDebuggable(package) }
    }

    private func waitForAgent() async -> Profiler_Proto_AgentData.Status? {
        while !Task.isCancelled {
            if let found = state.withLock({ $0.agentStatus }) { return found }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return nil
    }

    private func startInspector() async throws {
        var create = Profiler_Proto_CreateInspectorCommand()
        create.dexPath = PhoneInspectorPaths.networkInspector
        create.launchMetadata.launchedByName = "Benz Mirror"
        create.launchMetadata.force = true
        let created = try await sendInspectorCommand(.createInspectorCommand(create), timeout: 15)
        if created.status != .success { throw AppInspectorError.rejected(created.errorMessage.isEmpty ? String(localized: "it could not start") : created.errorMessage) }

        var start = Studio_Network_Inspection_Command()
        start.startInspectionCommand = Studio_Network_Inspection_StartInspectionCommand()
        var raw = Profiler_Proto_RawCommand()
        raw.content = try start.serializedData()
        let started = try await sendInspectorCommand(.rawInspectorCommand(raw), timeout: 15)
        if started.status != .success { throw AppInspectorError.rejected(started.errorMessage) }
    }

    private func sendInspectorCommand(_ body: Profiler_Proto_AppInspectionCommand.OneOf_Union, timeout: TimeInterval) async throws -> Profiler_Proto_AppInspectionResponse {
        let id = state.withLock { s -> UInt32 in s.nextCommand += 1; return s.nextCommand }
        var inspection = Profiler_Proto_AppInspectionCommand()
        inspection.inspectorID = inspectorID
        inspection.commandID = id
        inspection.union = body
        var command = Profiler_Proto_Command()
        command.type = .appInspection
        command.pid = pid
        command.commandID = Int32(id)
        command.appInspectionCommand = inspection
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Profiler_Proto_AppInspectionResponse, Error>) in
            state.withLock { $0.waiting[id] = continuation }
            Task { [weak self] in
                do { try await self?.execute(command) } catch { self?.resume(id, with: .failure(error)) }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.resume(id, with: .failure(AppInspectorError.noAnswer(String(localized: "starting the inspector"))))
            }
        }
    }

    private func resume(_ id: UInt32, with result: Result<Profiler_Proto_AppInspectionResponse, Error>) {
        let continuation = state.withLock { $0.waiting.removeValue(forKey: id) }
        continuation?.resume(with: result)
    }

    private func failPending(_ error: Error) {
        let all = state.withLock { s -> [CheckedContinuation<Profiler_Proto_AppInspectionResponse, Error>] in
            let values = Array(s.waiting.values); s.waiting = [:]; return values
        }
        all.forEach { $0.resume(throwing: error) }
    }

    // MARK: Events

    private func readEvents(_ client: Profiler_Proto_TransportServiceAsyncClient) async {
        var ended: String?
        do {
            for try await event in client.getEvents(Profiler_Proto_GetEventsRequest()) { handle(event) }
        } catch {
            ended = state.withLock { $0.stopped } ? nil : error.localizedDescription
        }
        if !state.withLock({ $0.stopped }) { onEnded(ended) }
    }

    private func handle(_ event: Profiler_Proto_Event) {
        switch event.union {
        case let .agentData(data)? where event.pid == pid:
            state.withLock { $0.agentStatus = data.status }
        case let .appInspectionResponse(response)?:
            resume(response.commandID, with: .success(response))
        case let .appInspectionPayload(payload)?:
            storeChunk(id: event.groupID, payload: payload)
        case let .appInspectionEvent(inspection)? where inspection.inspectorID == inspectorID:
            switch inspection.union {
            case let .rawEvent(raw)?:
                switch raw.data {
                case let .content(bytes)?: decode(bytes)
                case let .payloadID(id)?: decodePayload(id)
                case nil: break
                }
            case .disposedEvent?: onEnded(String(localized: "The app stopped the inspector."))
            case nil: break
            }
        default: break
        }
    }

    private func storeChunk(id: Int64, payload: Profiler_Proto_AppInspectionPayload) {
        let complete = state.withLock { s -> Data? in
            s.chunks[id, default: [:]][payload.chunkIndex] = payload.chunk
            s.chunkCounts[id] = payload.chunkCount
            guard let count = s.chunkCounts[id], UInt32(s.chunks[id]?.count ?? 0) >= count else { return nil }
            let joined = (0..<count).reduce(into: Data()) { $0.append(s.chunks[id]?[$1] ?? Data()) }
            s.chunks[id] = nil; s.chunkCounts[id] = nil
            return joined
        }
        if let complete { decode(complete) }
    }

    private func decodePayload(_ id: Int64) {
        let ready = state.withLock { s -> Data? in
            guard let count = s.chunkCounts[id], UInt32(s.chunks[id]?.count ?? 0) >= count else { return nil }
            let joined = (0..<count).reduce(into: Data()) { $0.append(s.chunks[id]?[$1] ?? Data()) }
            s.chunks[id] = nil; s.chunkCounts[id] = nil
            return joined
        }
        if let ready { decode(ready) }
    }

    private func decode(_ bytes: Data) {
        guard let event = try? Studio_Network_Inspection_Event(serializedBytes: bytes), let mapped = NetworkEventMapper.map(event) else { return }
        let call = state.withLock { $0.assembler.apply(mapped) }
        if let call { onCall(call) }
    }
}

enum PhoneTransferQuote {
    static func quote(_ text: String) -> String { PhoneTransfer.shellQuoted(text) }
}
