import Foundation
import DomainModels
import Networking

/// Streams `adb logcat` for one device and keeps the most recent lines, optionally only those of the app in front.
@MainActor
public final class LogcatModel: ObservableObject {
    public init() {}

    public nonisolated static let capacity = 5_000
    private static let processPollInterval = Duration.milliseconds(1_500)
    private static let maxHeldCrashLines = 200

    public enum Scope: String, CaseIterable, Identifiable {
        case foregroundApp, everything

        public var id: String { rawValue }
        public var title: String { self == .foregroundApp ? "App in front" : "Everything" }
    }

    @Published public private(set) var entries: [LogEntry] = []
    @Published public private(set) var isRunning = false
    /// Ids of the lines that open a crash, an ANR or a native crash, oldest first.
    @Published public private(set) var crashIDs: [Int] = []
    @Published public private(set) var foregroundPackage: String?
    @Published public var scope = Scope.foregroundApp
    @Published public var minimumLevel = LogLevel.verbose
    @Published public var filter = ""
    @Published public var isPaused = false

    private var process: Process?
    private var flushTask: Task<Void, Never>?
    private var processTask: Task<Void, Never>?
    private let incoming = LockedValue<[String]>([])
    private var nextID = 0
    private var grouper = CrashGrouper()
    /// Every process id seen for the app in front (a crashed app comes back with a new one, and its old lines still matter).
    private var processIDs: Set<Int> = []
    private var acceptedBlocks: Set<Int> = []
    private var held: HeldCrash?
    private var fetchProcesses: (@Sendable () throws -> String)?

    /// A crash that started in a process not yet known to be the app's. Its lines wait for the report's
    /// `Process: <package>, PID: n` line, which says whether it is.
    private struct HeldCrash {
        let block: Int
        let pid: Int?
        var lines: [LogEntry]
    }

    /// How many process ids are known for the app in front.
    public var knownProcessCount: Int { processIDs.count }

    public var visibleEntries: [LogEntry] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            entry.level >= minimumLevel && (query.isEmpty || entry.text.localizedCaseInsensitiveContains(query))
        }
    }

    // MARK: Running

    public func start(adb: ADB, serial: String) {
        stop()
        let process = adb.makeProcess(["-s", serial, "logcat", "-v", "threadtime"])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let buffer = LockedValue(LineBuffer())
        output.fileHandleForReading.readabilityHandler = { [incoming, buffer] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            let lines = buffer.withLock { $0.append(chunk) }
            guard !lines.isEmpty else { return }
            incoming.withLock {
                $0.append(contentsOf: lines)
                if $0.count > LogcatModel.capacity { $0.removeFirst($0.count - LogcatModel.capacity) } // bounded while paused
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.isRunning = false }
        }

        do { try process.run() } catch { return }
        self.process = process
        isRunning = true
        fetchProcesses = { String(decoding: try adb.run(["-s", serial, "shell", ProcessList.command], timeout: 5), as: UTF8.self) }

        // Lines are applied in batches so a busy device cannot flood the UI.
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                self?.flush()
            }
        }
        processTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshProcesses()
                try? await Task.sleep(for: Self.processPollInterval)
            }
        }
    }

    public func stop() {
        flushTask?.cancel()
        processTask?.cancel()
        flushTask = nil
        processTask = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        isRunning = false
    }

    public func clear() {
        entries.removeAll()
        crashIDs.removeAll()
        incoming.set([])
        acceptedBlocks.removeAll()
        held = nil
    }

    // MARK: The app in front

    /// Which app to follow. A different app starts with an empty process list, filled in at once.
    public func setForegroundPackage(_ package: String?) {
        guard package != foregroundPackage else { return }
        foregroundPackage = package
        processIDs = []
        held = nil
        Task { await refreshProcesses() }
    }

    public func refreshProcesses() async {
        guard scope == .foregroundApp, let package = foregroundPackage, let fetch = fetchProcesses else { return }
        guard let output = await Task.detached(operation: { try? fetch() }).value, package == foregroundPackage else { return }
        updateProcesses(from: output)
    }

    /// Adds the app's processes from a `ps` listing.
    public func updateProcesses(from output: String) {
        guard let package = foregroundPackage else { return }
        processIDs.formUnion(ProcessList.pids(of: package, in: ProcessList.parse(output)))
    }

    // MARK: Taking lines in

    private func flush() {
        guard !isPaused else { return } // lines wait in `incoming` until resumed
        let lines = incoming.withLock { pending -> [String] in
            defer { pending.removeAll() }
            return pending
        }
        ingest(lines)
    }

    /// Parses lines, groups crashes, and keeps what belongs to the chosen scope.
    public func ingest(_ lines: [String]) {
        var kept: [LogEntry] = []
        for line in lines {
            let entry = grouper.apply(to: LogEntry.parse(line, id: nextID))
            nextID += 1
            kept += accepted(entry)
        }
        guard !kept.isEmpty else { return }

        entries.append(contentsOf: kept)
        crashIDs.append(contentsOf: kept.filter { $0.kind.startsCrash }.map(\.id))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
            if let oldest = entries.first?.id { crashIDs.removeAll { $0 < oldest } }
        }
    }

    private func accepted(_ entry: LogEntry) -> [LogEntry] {
        guard scope == .foregroundApp, let package = foregroundPackage else { return [entry] }
        let belongs = LogScope.accepts(entry, package: package, pids: processIDs, acceptedBlocks: acceptedBlocks)

        if var pending = held {
            if entry.crashBlock == pending.block {
                if entry.pid == pending.pid, let pid = LogScope.crashPID(in: entry.message, package: package) {
                    processIDs.insert(pid) // the report names the app: it was ours after all
                    acceptedBlocks.insert(pending.block)
                    held = nil
                    return pending.lines + [entry]
                }
                if pending.lines.count < Self.maxHeldCrashLines { pending.lines.append(entry); held = pending }
                return []
            }
            if entry.pid == pending.pid { held = nil } // the process went on logging: not a crash report of the app
        }

        if entry.kind.startsCrash, !belongs, let block = entry.crashBlock {
            held = HeldCrash(block: block, pid: entry.pid, lines: [entry])
            return []
        }
        guard belongs else { return [] }
        if entry.kind.startsCrash, let block = entry.crashBlock { acceptedBlocks.insert(block) }
        return [entry]
    }
}
