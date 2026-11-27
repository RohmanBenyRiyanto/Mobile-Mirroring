import XCTest
@testable import DomainModels

final class SmoothScrollTests: XCTestCase {
    func testStrokeFollowsTheFingerAndStaysOnScreen() {
        var stroke = ScrollStroke()
        XCTAssertEqual(stroke.begin(at: CGPoint(x: 0.5, y: 0.5)), [.down(CGPoint(x: 0.5, y: 0.5))])
        XCTAssertTrue(stroke.begin(at: CGPoint(x: 0.1, y: 0.1)).isEmpty, "a second begin is ignored")
        XCTAssertEqual(stroke.move(by: CGVector(dx: 0, dy: -0.2)), [.move(CGPoint(x: 0.5, y: 0.3))])
        XCTAssertEqual(stroke.move(by: CGVector(dx: 0, dy: -5)), [.move(CGPoint(x: 0.5, y: ScrollStroke.safeRange.lowerBound))])
        XCTAssertTrue(stroke.move(by: CGVector(dx: 0, dy: -1)).isEmpty, "no event once at the edge")
        XCTAssertEqual(stroke.end(), [.up(CGPoint(x: 0.5, y: ScrollStroke.safeRange.lowerBound))])
        XCTAssertTrue(stroke.end().isEmpty)
        XCTAssertTrue(stroke.move(by: CGVector(dx: 0.1, dy: 0)).isEmpty)
    }

    func testStartPointIsKeptInsideTheSafeBand() {
        var stroke = ScrollStroke()
        XCTAssertEqual(stroke.begin(at: CGPoint(x: 0, y: 1)), [.down(CGPoint(x: 0.06, y: 0.94))])
    }

    func testArrowTravelRampsThenHoldsSteady() {
        let scroll = ArrowScroll()
        XCTAssertEqual(scroll.travel(heldFor: 0), 0)
        XCTAssertLessThan(scroll.travel(heldFor: 0.06), scroll.travel(heldFor: 0.12))
        let a = scroll.travel(heldFor: 1.0), b = scroll.travel(heldFor: 2.0)
        XCTAssertEqual(b - a, scroll.topSpeed, accuracy: 1e-9)
        XCTAssertEqual(scroll.travel(heldFor: -1), 0)
    }

    func testATapStillMovesAVisibleStep() {
        let scroll = ArrowScroll()
        XCTAssertEqual(scroll.remainingAtRelease(travelled: 0.02), 0.18, accuracy: 1e-9)
        XCTAssertEqual(scroll.remainingAtRelease(travelled: 0.5), 0)
    }
}
