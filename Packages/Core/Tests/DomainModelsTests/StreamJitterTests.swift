import XCTest
@testable import DomainModels

final class StreamJitterTests: XCTestCase {
    func testSteadyArrivalHasNoJitterAndUnevenArrivalHas() {
        let steady = StreamStatistics()
        let start = Date()
        for i in 0..<120 {
            steady.recordVideoPacket(bytes: 1000, isFrame: true, presentationMicros: Int64(i) * 16_667, arrival: start.addingTimeInterval(Double(i) * 0.016667))
        }
        XCTAssertLessThan(steady.snapshot().jitterMillis, 0.5)

        let uneven = StreamStatistics()
        for i in 0..<120 {
            let late = i.isMultiple(of: 2) ? 0.012 : 0
            uneven.recordVideoPacket(bytes: 1000, isFrame: true, presentationMicros: Int64(i) * 16_667, arrival: start.addingTimeInterval(Double(i) * 0.016667 + late))
        }
        XCTAssertGreaterThan(uneven.snapshot().jitterMillis, 5)
    }

    func testStillScreenGapsAreNotJitter() {
        let stats = StreamStatistics()
        let start = Date()
        stats.recordVideoPacket(bytes: 1, isFrame: true, presentationMicros: 0, arrival: start)
        stats.recordVideoPacket(bytes: 1, isFrame: true, presentationMicros: 3_000_000, arrival: start.addingTimeInterval(3.2))
        XCTAssertEqual(stats.snapshot().jitterMillis, 0)
    }

    func testConfigPacketsAndMissingTimesAreIgnored() {
        let stats = StreamStatistics()
        stats.recordVideoPacket(bytes: 10, isFrame: false, presentationMicros: 5)
        stats.recordVideoPacket(bytes: 10, isFrame: true)
        XCTAssertEqual(stats.snapshot().jitterMillis, 0)
    }
}
