import XCTest
@testable import DomainModels
@testable import Persistence

final class ControlMessageTests: XCTestCase {
    private let position = TouchPosition(x: 100, y: 200, frameWidth: 1080, frameHeight: 2400)

    func testKeycodeLayout() {
        let bytes = [UInt8](ControlMessage.keycode(.down, .back).serialized)
        XCTAssertEqual(bytes, [0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    func testTouchDownLayout() {
        let data = ControlMessage.touch(.down, position, pressure: 1).serialized
        XCTAssertEqual(data.count, 32)
        XCTAssertEqual(data[0], 2) // type
        XCTAssertEqual(data[1], 0) // action down
        XCTAssertEqual(data.readBigEndian(UInt64.self, at: 2), .max) // mouse pointer id
        XCTAssertEqual(data.readBigEndian(Int32.self, at: 10), 100)
        XCTAssertEqual(data.readBigEndian(Int32.self, at: 14), 200)
        XCTAssertEqual(data.readBigEndian(UInt16.self, at: 18), 1080)
        XCTAssertEqual(data.readBigEndian(UInt16.self, at: 20), 2400)
        XCTAssertEqual(data.readBigEndian(UInt16.self, at: 22), 0xFFFF) // full pressure
        XCTAssertEqual(data.readBigEndian(UInt32.self, at: 24), 1) // action button
        XCTAssertEqual(data.readBigEndian(UInt32.self, at: 28), 1) // buttons held
    }

    func testTouchUpReleasesButtons() {
        let data = ControlMessage.touch(.up, position, pressure: 0).serialized
        XCTAssertEqual(data[1], 1)
        XCTAssertEqual(data.readBigEndian(UInt16.self, at: 22), 0)
        XCTAssertEqual(data.readBigEndian(UInt32.self, at: 28), 0)
    }

    func testScrollLayout() {
        let data = ControlMessage.scroll(position, horizontal: 0, vertical: -16).serialized
        XCTAssertEqual(data.count, 21)
        XCTAssertEqual(data.readBigEndian(Int16.self, at: 13), 0)
        XCTAssertEqual(data.readBigEndian(Int16.self, at: 15), Int16.min)
    }

    func testTextIsTruncatedWithoutSplittingCharacters() {
        let data = ControlMessage.text(String(repeating: "é", count: 400)).serialized // 2 bytes each
        let length = Int(data.readBigEndian(UInt32.self, at: 1))
        XCTAssertEqual(length, 300)
        XCTAssertEqual(data.count, 5 + length)
        XCTAssertNotNil(String(data: data.suffix(length), encoding: .utf8))
    }

    func testSetClipboardLayout() {
        let data = ControlMessage.setClipboard("hi", paste: true).serialized
        XCTAssertEqual(data[0], 9)
        XCTAssertEqual(data[9], 1) // paste flag
        XCTAssertEqual(data.readBigEndian(UInt32.self, at: 10), 2)
        XCTAssertEqual(String(data: data.suffix(2), encoding: .utf8), "hi")
    }

    func testFixedPointClamping() {
        XCTAssertEqual(ControlMessage.unsignedFixedPoint(2), 0xFFFF)
        XCTAssertEqual(ControlMessage.unsignedFixedPoint(-1), 0)
        XCTAssertEqual(ControlMessage.signedFixedPoint(5), Int16.max)
        XCTAssertEqual(ControlMessage.signedFixedPoint(-5), Int16.min)
    }
}
