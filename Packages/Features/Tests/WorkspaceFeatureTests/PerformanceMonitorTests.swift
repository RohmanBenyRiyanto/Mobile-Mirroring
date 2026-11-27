import DomainModels
import XCTest
@testable import WorkspaceFeature

@MainActor
final class PerformanceMonitorTests: XCTestCase {
    func testFirstReadingOnlySetsTheBaseline() {
        let monitor = PerformanceMonitor()
        monitor.ingest(PerformanceReading(cpuTotalTicks: 100, totalFrames: 10), package: "a.b")
        XCTAssertNil(monitor.latest)
        XCTAssertTrue(monitor.history.samples.isEmpty)
    }

    func testSecondReadingProducesASampleAndSwitchingAppsStartsOver() {
        let monitor = PerformanceMonitor()
        let start = ContinuousClock.now
        monitor.ingest(PerformanceReading(cpuTotalTicks: 100, totalFrames: 10), package: "a.b", now: start)
        monitor.ingest(PerformanceReading(cpuTotalTicks: 200, totalFrames: 70), package: "a.b", now: start + .seconds(1))
        XCTAssertEqual(monitor.latest?.framesPerSecond ?? 0, 60, accuracy: 0.1)
        XCTAssertEqual(monitor.history.samples.count, 1)

        monitor.ingest(PerformanceReading(cpuTotalTicks: 300, totalFrames: 5), package: "c.d", now: start + .seconds(2))
        XCTAssertNil(monitor.latest)
        XCTAssertTrue(monitor.history.samples.isEmpty)
        XCTAssertEqual(monitor.package, "c.d")
    }
}
