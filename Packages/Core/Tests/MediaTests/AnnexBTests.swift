import XCTest
@testable import Media
@testable import DomainModels
@testable import CoreTestSupport

final class AnnexBTests: XCTestCase {
    func testSplitsThreeAndFourByteStartCodes() {
        let stream = Data([0, 0, 0, 1, 0x67, 0xAA, 0, 0, 1, 0x68, 0xBB, 0xCC])
        XCTAssertEqual(AnnexB.nalUnits(in: stream), [Data([0x67, 0xAA]), Data([0x68, 0xBB, 0xCC])])
    }

    func testIgnoresGarbageWithoutStartCode() {
        XCTAssertTrue(AnnexB.nalUnits(in: Data([1, 2, 3, 4, 5])).isEmpty)
        XCTAssertTrue(AnnexB.nalUnits(in: Data()).isEmpty)
    }

    func testLengthPrefixingDropsExcludedUnits() {
        let stream = Data([0, 0, 0, 1, 0x67, 0xAA, 0, 0, 0, 1, 0x65, 1, 2, 3])
        let output = AnnexB.lengthPrefixed(stream) { $0 & 0x1F == 7 } // drop SPS
        XCTAssertEqual([UInt8](output), [0, 0, 0, 4, 0x65, 1, 2, 3])
    }
}
