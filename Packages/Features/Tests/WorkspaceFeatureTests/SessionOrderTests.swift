import XCTest
@testable import DomainModels
@testable import WorkspaceFeature

final class SessionOrderTests: XCTestCase {
    func testRemovingTheActivePhoneSelectsItsNeighbour() {
        XCTAssertEqual(SessionOrder.activeSerial(afterRemoving: "b", from: ["a", "b", "c"], active: "b"), "a", "the previous tab")
        XCTAssertEqual(SessionOrder.activeSerial(afterRemoving: "a", from: ["a", "b", "c"], active: "a"), "b", "no previous: the first remaining")
        XCTAssertEqual(SessionOrder.activeSerial(afterRemoving: "c", from: ["a", "b", "c"], active: "c"), "b")
    }

    func testRemovingAnotherPhoneKeepsTheActiveOne() {
        XCTAssertEqual(SessionOrder.activeSerial(afterRemoving: "c", from: ["a", "b", "c"], active: "a"), "a")
        XCTAssertEqual(SessionOrder.activeSerial(afterRemoving: "a", from: ["a", "b", "c"], active: "c"), "c")
    }

    func testRemovingTheLastPhoneLeavesNothing() {
        XCTAssertNil(SessionOrder.activeSerial(afterRemoving: "a", from: ["a"], active: "a"))
        XCTAssertNil(SessionOrder.activeSerial(afterRemoving: "a", from: [], active: nil))
    }

    func testRemovingAnUnknownPhoneChangesNothing() {
        XCTAssertEqual(SessionOrder.activeSerial(afterRemoving: "z", from: ["a", "b"], active: "b"), "b")
        XCTAssertEqual(SessionOrder.activeSerial(afterRemoving: "z", from: ["a", "b"], active: nil), "a")
    }

    func testEachPhoneGetsItsOwnStreamPort() {
        XCTAssertEqual(SessionOrder.streamPort(base: 8765, taken: []), 8765)
        XCTAssertEqual(SessionOrder.streamPort(base: 8765, taken: [8765]), 8766)
        XCTAssertEqual(SessionOrder.streamPort(base: 8765, taken: [8765, 8766, 8767]), 8768)
        XCTAssertEqual(SessionOrder.streamPort(base: 8765, taken: [9000]), 8765, "unrelated ports do not matter")
    }

    func testStreamPortStaysInRangeAndKeepsAnyFreePortRequests() {
        XCTAssertEqual(SessionOrder.streamPort(base: 0, taken: [0]), 0, "0 means any free port")
        XCTAssertEqual(SessionOrder.streamPort(base: 65535, taken: [65535]), MirrorSettings.streamPortRange.lowerBound, "wraps around")
        XCTAssertEqual(SessionOrder.streamPort(base: 80, taken: []), MirrorSettings.streamPortRange.lowerBound, "ports below 1024 are not used")
        XCTAssertTrue(MirrorSettings.streamPortRange.contains(SessionOrder.streamPort(base: 70_000, taken: [])))
    }
}
