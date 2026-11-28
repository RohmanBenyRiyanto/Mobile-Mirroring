import Foundation

// MARK: Raw reading

public struct PerformanceReading: Equatable, Sendable {
    public var cpuTotalTicks: Int
    public var cpuIdleTicks: Int
    public var appCPUTicks: Int?
    public var appMemoryKB: Int?
    public var memoryTotalKB: Int?
    public var memoryAvailableKB: Int?
    public var batteryTenthsCelsius: Int?
    public var batteryLevel: Int?
    public var totalFrames: Int?
    public var jankyFrames: Int?
    public var uptimeMillis: Int?

    public init(cpuTotalTicks: Int = 0, cpuIdleTicks: Int = 0, appCPUTicks: Int? = nil, appMemoryKB: Int? = nil,
                memoryTotalKB: Int? = nil, memoryAvailableKB: Int? = nil, batteryTenthsCelsius: Int? = nil,
                batteryLevel: Int? = nil, totalFrames: Int? = nil, jankyFrames: Int? = nil, uptimeMillis: Int? = nil) {
        self.cpuTotalTicks = cpuTotalTicks
        self.cpuIdleTicks = cpuIdleTicks
        self.appCPUTicks = appCPUTicks
        self.appMemoryKB = appMemoryKB
        self.memoryTotalKB = memoryTotalKB
        self.memoryAvailableKB = memoryAvailableKB
        self.batteryTenthsCelsius = batteryTenthsCelsius
        self.batteryLevel = batteryLevel
        self.totalFrames = totalFrames
        self.jankyFrames = jankyFrames
        self.uptimeMillis = uptimeMillis
    }
}

public enum PerformanceProbe {
    public static let pageSizeKB = 4

    public static func command(package: String) -> String {
        precondition(package.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }, "package name")
        return "echo '##STAT'; head -1 /proc/stat; "
            + "echo '##PROC'; P=$(pidof \(package)); P=${P%% *}; [ -n \"$P\" ] && cat /proc/$P/stat /proc/$P/statm; "
            + "echo '##MEM'; grep -E 'MemTotal|MemAvailable' /proc/meminfo; "
            + "echo '##BAT'; dumpsys battery | grep -E '^  (level|temperature):'; "
            + "echo '##GFX'; dumpsys gfxinfo \(package) | grep -E 'Total frames rendered|Janky frames:|Uptime:'"
    }

    public static func parse(_ output: String) -> PerformanceReading {
        var sections: [String: [Substring]] = [:]
        var current = ""
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("##") { current = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces); continue }
            sections[current, default: []].append(line)
        }
        var reading = PerformanceReading()

        if let cpu = sections["STAT"]?.first {
            let ticks = cpu.split(separator: " ").dropFirst().compactMap { Int($0) }
            reading.cpuTotalTicks = ticks.reduce(0, +)
            if ticks.count > 4 { reading.cpuIdleTicks = ticks[3] + ticks[4] }
        }
        if let lines = sections["PROC"], let stat = lines.first {
            if let close = stat.lastIndex(of: ")") {
                let fields = stat[stat.index(after: close)...].split(separator: " ")
                if fields.count > 12, let user = Int(fields[11]), let system = Int(fields[12]) { reading.appCPUTicks = user + system }
            }
            if lines.count > 1 {
                let statm = lines[1].split(separator: " ")
                if statm.count > 1, let resident = Int(statm[1]) { reading.appMemoryKB = resident * pageSizeKB }
            }
        }
        for line in sections["MEM"] ?? [] {
            if line.hasPrefix("MemTotal:") { reading.memoryTotalKB = firstNumber(in: line) }
            if line.hasPrefix("MemAvailable:") { reading.memoryAvailableKB = firstNumber(in: line) }
        }
        for line in sections["BAT"] ?? [] {
            if line.contains("temperature:") { reading.batteryTenthsCelsius = firstNumber(in: line) }
            if line.contains("level:") { reading.batteryLevel = firstNumber(in: line) }
        }
        for line in sections["GFX"] ?? [] {
            if line.contains("Total frames rendered:") { reading.totalFrames = firstNumber(in: line) }
            if line.contains("Janky frames:") && !line.contains("legacy") { reading.jankyFrames = firstNumber(in: line) }
            if line.hasPrefix("Uptime:") { reading.uptimeMillis = firstNumber(in: line) }
        }
        return reading
    }

    private static func firstNumber(in line: Substring) -> Int? {
        line.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
    }
}

// MARK: Derived sample

public struct PerformanceSample: Equatable, Sendable {
    public var framesPerSecond: Double?
    public var jankPercent: Double?
    public var appCPUPercent: Double?
    public var systemCPUPercent: Double
    public var appMemoryMB: Double?
    public var memoryUsedPercent: Double?
    public var temperatureCelsius: Double?
    public var batteryLevel: Int?

    public static func between(_ old: PerformanceReading, _ new: PerformanceReading, seconds: Double) -> PerformanceSample {
        let totalDelta = new.cpuTotalTicks - old.cpuTotalTicks
        let idleDelta = new.cpuIdleTicks - old.cpuIdleTicks
        let system = totalDelta > 0 ? clamp(Double(totalDelta - idleDelta) / Double(totalDelta) * 100) : 0

        var app: Double?
        if totalDelta > 0, let a = new.appCPUTicks, let b = old.appCPUTicks, a >= b { app = clamp(Double(a - b) / Double(totalDelta) * 100) }

        var fps: Double?, jank: Double?
        if let frames = new.totalFrames, let before = old.totalFrames, frames >= before, seconds > 0 {
            let delta = frames - before
            fps = Double(delta) / seconds
            if delta > 0, let j = new.jankyFrames, let jb = old.jankyFrames, j >= jb { jank = clamp(Double(j - jb) / Double(delta) * 100) }
            else if delta == 0 { jank = 0 }
        }

        var used: Double?
        if let total = new.memoryTotalKB, total > 0, let available = new.memoryAvailableKB { used = clamp(Double(total - available) / Double(total) * 100) }

        return PerformanceSample(
            framesPerSecond: fps, jankPercent: jank, appCPUPercent: app, systemCPUPercent: system,
            appMemoryMB: new.appMemoryKB.map { Double($0) / 1024 }, memoryUsedPercent: used,
            temperatureCelsius: new.batteryTenthsCelsius.map { Double($0) / 10 }, batteryLevel: new.batteryLevel)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 100) }
}

// MARK: Warnings and history

public enum PerformanceWarning: Equatable, Sendable {
    case hot, lowMemory, jank, busyCPU

    public static func warnings(for sample: PerformanceSample) -> [PerformanceWarning] {
        var found: [PerformanceWarning] = []
        if let t = sample.temperatureCelsius, t >= 42 { found.append(.hot) }
        if let m = sample.memoryUsedPercent, m >= 90 { found.append(.lowMemory) }
        if let j = sample.jankPercent, j >= 20 { found.append(.jank) }
        if sample.systemCPUPercent >= 90 { found.append(.busyCPU) }
        return found
    }
}

public struct PerformanceHistory: Equatable, Sendable {
    public static let capacity = 120
    public private(set) var samples: [PerformanceSample] = []

    public init() {}

    public mutating func append(_ sample: PerformanceSample) {
        samples.append(sample)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    public mutating func reset() { samples.removeAll() }

    public func csv() -> String {
        func cell(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "" }
        var rows = ["second,fps,jank_percent,app_cpu_percent,system_cpu_percent,app_memory_mb,memory_used_percent,temperature_c"]
        for (i, s) in samples.enumerated() {
            rows.append([String(i), cell(s.framesPerSecond), cell(s.jankPercent), cell(s.appCPUPercent), cell(s.systemCPUPercent),
                         cell(s.appMemoryMB), cell(s.memoryUsedPercent), cell(s.temperatureCelsius)].joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
