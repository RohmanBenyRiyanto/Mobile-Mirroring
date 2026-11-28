import XCTest
@testable import DomainModels

final class VirtualDisplayTests: XCTestCase {
    func testWindowBecomesAnEncoderFriendlySize() {
        let size = VirtualDisplayMath.size(forViewPoints: CGSize(width: 800, height: 600), backingScale: 2, maxLongEdge: 1920)
        XCTAssertEqual(size?.width, 1600)
        XCTAssertEqual(size?.height, 1200)
        let small = VirtualDisplayMath.size(forViewPoints: CGSize(width: 405, height: 723), backingScale: 1, maxLongEdge: 1920)
        XCTAssertEqual(small?.width, 400)
        XCTAssertEqual(small?.height, 720)
        XCTAssertNil(VirtualDisplayMath.size(forViewPoints: .zero, backingScale: 2, maxLongEdge: 1920))
        XCTAssertEqual(VirtualDisplayMath.size(forViewPoints: CGSize(width: 10, height: 10), backingScale: 1, maxLongEdge: 1920)?.width, 320)
    }

    func testDensityKeepsPhoneLikeLayouts() {
        XCTAssertEqual(VirtualDisplayMath.density(shortEdge: 1080), 420)
        XCTAssertEqual(VirtualDisplayMath.density(shortEdge: 100), 120)
        XCTAssertEqual(VirtualDisplayMath.density(shortEdge: 9000), 640)
    }

    func testSmallDragsAreNotSent() {
        XCTAssertTrue(VirtualDisplayMath.isWorthSending(old: nil, new: (800, 600)))
        XCTAssertFalse(VirtualDisplayMath.isWorthSending(old: (800, 600), new: (808, 600)))
        XCTAssertTrue(VirtualDisplayMath.isWorthSending(old: (800, 600), new: (824, 600)))
    }

    func testServerArgumentsOnlyWhenEnabledAndWithAValidApp() {
        var settings = MirrorSettings()
        XCTAssertFalse(settings.serverArguments(scid: 1).contains { $0.hasPrefix("new_display") })
        settings.virtualDisplay = VirtualDisplaySettings(isEnabled: true, startApp: "com.example.game")
        let arguments = settings.serverArguments(scid: 1)
        XCTAssertTrue(arguments.contains("new_display=1080x1920/420"))
        XCTAssertTrue(arguments.contains("flex_display=true"))
        XCTAssertTrue(arguments.contains("vd_destroy_content=false"))
        XCTAssertFalse(arguments.contains { $0.hasPrefix("start_app") }, "the app is opened by a control message")
        XCTAssertEqual(settings.virtualDisplayApp, "com.example.game")
        settings.virtualDisplay.startApp = "bad; reboot"
        XCTAssertNil(settings.virtualDisplayApp)
    }

    func testStartAppMessageCarriesTheNameLength() {
        XCTAssertEqual(ControlMessage.startApp("a.b").serialized, Data([16, 3]) + Data("a.b".utf8))
    }

    func testResizeMessageIsTypeTwentyOneWithTwoBigEndianShorts() {
        XCTAssertEqual(ControlMessage.resizeDisplay(width: 1280, height: 720).serialized, Data([21, 0x05, 0x00, 0x02, 0xD0]))
    }
}
