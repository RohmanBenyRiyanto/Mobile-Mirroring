import XCTest
@testable import DomainModels

final class PerformanceSamplingTests: XCTestCase {
    private let first = """
    ##STAT
    cpu  25498134 1743761 20717799 253714341 444598 4106176 819554 7511 0 0
    ##PROC
    4888 (id.app.launcher) S 1727 1727 0 0 -1 1077936448 11868441 0 6118461 0 140119 117551 0 0 10 -10 96 0 3270 11332665344 45540 18446744073709551615
    2766764 45540 21383 2 0 1000899 0
    ##MEM
    MemTotal:        7242448 kB
    MemAvailable:    1708744 kB
    ##BAT
      level: 100
      temperature: 323
    ##GFX
    Uptime: 390644867 Realtime: 597355184
    Total frames rendered: 40327
    Janky frames: 2201 (5.46%)
    Janky frames (legacy): 3362 (8.34%)
    """

    func testParsesEveryCounterFromRealOutput() {
        let r = PerformanceProbe.parse(first)
        XCTAssertEqual(r.cpuTotalTicks, 25498134 + 1743761 + 20717799 + 253714341 + 444598 + 4106176 + 819554 + 7511)
        XCTAssertEqual(r.cpuIdleTicks, 253714341 + 444598)
        XCTAssertEqual(r.appCPUTicks, 140119 + 117551)
        XCTAssertEqual(r.appMemoryKB, 45540 * 4)
        XCTAssertEqual(r.memoryTotalKB, 7242448)
        XCTAssertEqual(r.memoryAvailableKB, 1708744)
        XCTAssertEqual(r.batteryTenthsCelsius, 323)
        XCTAssertEqual(r.batteryLevel, 100)
        XCTAssertEqual(r.totalFrames, 40327)
        XCTAssertEqual(r.jankyFrames, 2201)
    }

    func testProcessNameWithSpacesDoesNotShiftFields() {
        let out = "##PROC\n12 (my app (x)) S 1 1 0 0 -1 0 0 0 0 0 10 5 0 0 10 -10 1 0 1 1 1\n1 100 1 1 0 1 0\n"
        let r = PerformanceProbe.parse(out)
        XCTAssertEqual(r.appCPUTicks, 15)
        XCTAssertEqual(r.appMemoryKB, 400)
    }

    func testMissingSectionsStayNil() {
        let r = PerformanceProbe.parse("##STAT\ncpu  1 1 1 1 1 1 1 1\n##PROC\n##GFX\n")
        XCTAssertNil(r.appCPUTicks)
        XCTAssertNil(r.totalFrames)
    }

    func testSampleFromTwoReadings() {
        var a = PerformanceReading(cpuTotalTicks: 1000, cpuIdleTicks: 800, appCPUTicks: 10, totalFrames: 100, jankyFrames: 5)
        a.appMemoryKB = 2048
        let b = PerformanceReading(cpuTotalTicks: 1200, cpuIdleTicks: 900, appCPUTicks: 30, appMemoryKB: 4096, memoryTotalKB: 1000, memoryAvailableKB: 250,
                                   batteryTenthsCelsius: 355, totalFrames: 160, jankyFrames: 11)
        let s = PerformanceSample.between(a, b, seconds: 1)
        XCTAssertEqual(s.framesPerSecond, 60)
        XCTAssertEqual(s.jankPercent ?? 0, 10, accuracy: 0.01)
        XCTAssertEqual(s.appCPUPercent ?? 0, 10, accuracy: 0.01)
        XCTAssertEqual(s.systemCPUPercent, 50, accuracy: 0.01)
        XCTAssertEqual(s.appMemoryMB, 4)
        XCTAssertEqual(s.memoryUsedPercent, 75)
        XCTAssertEqual(s.temperatureCelsius, 35.5)
    }

    func testCounterResetAfterAppRestartGivesNoFrames() {
        let a = PerformanceReading(cpuTotalTicks: 10, totalFrames: 500, jankyFrames: 50)
        let b = PerformanceReading(cpuTotalTicks: 20, totalFrames: 10, jankyFrames: 1)
        let s = PerformanceSample.between(a, b, seconds: 1)
        XCTAssertNil(s.framesPerSecond)
        XCTAssertNil(s.jankPercent)
    }

    func testIdleScreenIsZeroFramesNotMissing() {
        let a = PerformanceReading(cpuTotalTicks: 10, totalFrames: 500, jankyFrames: 50)
        let s = PerformanceSample.between(a, a, seconds: 1)
        XCTAssertEqual(s.framesPerSecond, 0)
        XCTAssertEqual(s.jankPercent, 0)
    }

    func testWarnings() {
        var s = PerformanceSample.between(.init(), .init(), seconds: 1)
        XCTAssertTrue(PerformanceWarning.warnings(for: s).isEmpty)
        s.temperatureCelsius = 44; s.memoryUsedPercent = 95; s.jankPercent = 30; s.systemCPUPercent = 95
        XCTAssertEqual(Set(PerformanceWarning.warnings(for: s)), [.hot, .lowMemory, .jank, .busyCPU])
    }

    func testHistoryIsCappedAndCSVHasHeaderAndBlankForMissing() {
        var h = PerformanceHistory()
        for i in 0..<(PerformanceHistory.capacity + 10) {
            h.append(PerformanceSample(framesPerSecond: Double(i), systemCPUPercent: 1))
        }
        XCTAssertEqual(h.samples.count, PerformanceHistory.capacity)
        XCTAssertEqual(h.samples.first?.framesPerSecond, 10)
        let lines = h.csv().split(separator: "\n")
        XCTAssertEqual(lines.count, PerformanceHistory.capacity + 1)
        XCTAssertTrue(lines[1].hasSuffix(",1.0,,,"))
        h.reset()
        XCTAssertTrue(h.samples.isEmpty)
    }

    func testCommandRejectsUnsafePackageName() {
        XCTAssertTrue(PerformanceProbe.command(package: "com.a.b").contains("pidof com.a.b"))
    }
}
