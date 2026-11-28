import XCTest
@testable import DomainModels
@testable import Persistence

final class DeviceInfoTests: XCTestCase {
    private let real = """
    Physical size: 1080x2340
    Physical density: 480
    release=17
    sdk=37
    maker=samsung
    model=SM-S911B
    """

    func testParsesTheRealPhoneOutput() throws {
        let info = try XCTUnwrap(DeviceInfoParser.parse(real))
        XCTAssertEqual(info.physicalSize, CGSize(width: 1080, height: 2340))
        XCTAssertEqual(info.density, 480)
        XCTAssertEqual(info.sdk, 37)
        XCTAssertEqual(info.androidRelease, "17")
        XCTAssertEqual(info.manufacturer, "samsung")
        XCTAssertEqual(info.model, "SM-S911B")
        XCTAssertNil(info.overrideSize)
    }

    func testOverridesTakePrecedence() throws {
        let output = real + "\nOverride size: 720x1560\nOverride density: 320"
        let info = try XCTUnwrap(DeviceInfoParser.parse(output))
        XCTAssertEqual(info.screenSize, CGSize(width: 720, height: 1560))
        XCTAssertEqual(info.density, 320)
        XCTAssertEqual(info.physicalSize, CGSize(width: 1080, height: 2340), "the real values stay available for restoring")
        XCTAssertEqual(info.physicalDensity, 480)
    }

    func testDensityIndependentPixelsMatchTheRealPhone() throws {
        let info = try XCTUnwrap(DeviceInfoParser.parse(real))
        XCTAssertEqual(info.densityScale, 3)
        XCTAssertEqual(info.dp(fromPixels: 1080), 360, "the phone reports sw360dp")
        XCTAssertEqual(info.pixels(fromDP: 48), 144)
    }

    func testScreenSizeFollowsTheFrameOrientation() throws {
        let info = try XCTUnwrap(DeviceInfoParser.parse(real))
        XCTAssertEqual(info.screenSize(matching: CGSize(width: 540, height: 1170)), CGSize(width: 1080, height: 2340))
        XCTAssertEqual(info.screenSize(matching: CGSize(width: 2340, height: 1080)), CGSize(width: 2340, height: 1080))
    }

    func testIncompleteOrAbsurdOutputIsRejected() {
        XCTAssertNil(DeviceInfoParser.parse(""))
        XCTAssertNil(DeviceInfoParser.parse("Physical size: 1080x2340"), "density missing")
        XCTAssertNil(DeviceInfoParser.parse("Physical size: 0x0\nPhysical density: 480"))
        XCTAssertNil(DeviceInfoParser.parse("Physical size: 99999x99999\nPhysical density: 480"))
        XCTAssertNil(DeviceInfoParser.parse("Physical size: 1080x2340\nPhysical density: 9"))
    }

    func testTextFromThePhoneIsCleanedAndBounded() throws {
        let output = real.replacingOccurrences(of: "SM-S911B", with: "Evil\u{1B}[31m" + String(repeating: "x", count: 500))
        let info = try XCTUnwrap(DeviceInfoParser.parse(output))
        XCTAssertFalse(info.model.unicodeScalars.contains { $0.value < 0x20 })
        XCTAssertLessThanOrEqual(info.model.count, 64)
    }

    func testTheQueryIsAFixedConstant() {
        XCTAssertFalse(DeviceInfoParser.command.contains("\n"))
        XCTAssertTrue(DeviceInfoParser.command.hasPrefix("wm size"))
    }
}

final class CoordinateMapperTests: XCTestCase {
    private let phone = CGSize(width: 1080, height: 2340)

    func testVideoIsLetterboxedInsideAWiderView() {
        let mapper = CoordinateMapper(viewSize: CGSize(width: 800, height: 600), frameSize: phone)
        let rect = mapper.videoRect
        XCTAssertEqual(rect.height, 600, accuracy: 0.001)
        XCTAssertEqual(rect.width, 600 * 1080 / 2340, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 400, accuracy: 0.001, "centered")
    }

    func testBlackBarsHaveNoRatioButDragsClampToTheEdge() {
        let mapper = CoordinateMapper(viewSize: CGSize(width: 800, height: 600), frameSize: phone)
        XCTAssertNil(mapper.ratio(forViewPoint: CGPoint(x: 5, y: 300)))
        XCTAssertEqual(mapper.clampedRatio(forViewPoint: CGPoint(x: 5, y: 300))?.x, 0)
        XCTAssertEqual(mapper.clampedRatio(forViewPoint: CGPoint(x: 799, y: 9_999))?.x, 1)
        XCTAssertEqual(mapper.clampedRatio(forViewPoint: CGPoint(x: 400, y: 9_999))?.y, 1)
    }

    func testCornersAndCenterMapToFramePixels() throws {
        let mapper = CoordinateMapper(viewSize: CGSize(width: 540, height: 1170), frameSize: phone)
        let topLeft = try XCTUnwrap(mapper.touchPosition(forViewPoint: CGPoint(x: 0, y: 0)))
        let bottomRight = try XCTUnwrap(mapper.touchPosition(forViewPoint: CGPoint(x: 540, y: 1170)))
        let center = try XCTUnwrap(mapper.touchPosition(forViewPoint: CGPoint(x: 270, y: 585)))
        XCTAssertEqual([topLeft.x, topLeft.y], [0, 0])
        XCTAssertEqual([bottomRight.x, bottomRight.y], [1079, 2339])
        XCTAssertEqual(Double(center.x), 539.5, accuracy: 0.51)
        XCTAssertEqual(Double(center.y), 1169.5, accuracy: 0.51)
        XCTAssertEqual(center.frameWidth, 1080)
        XCTAssertEqual(center.frameHeight, 2340)
    }

    func testViewRatioViewRoundTrips() throws {
        let mapper = CoordinateMapper(viewSize: CGSize(width: 800, height: 600), frameSize: phone)
        for point in [CGPoint(x: 300, y: 100), CGPoint(x: 400, y: 599), CGPoint(x: 350, y: 1)] {
            let ratio = try XCTUnwrap(mapper.ratio(forViewPoint: point))
            let back = mapper.viewPoint(forRatio: ratio)
            XCTAssertEqual(back.x, point.x, accuracy: 0.001)
            XCTAssertEqual(back.y, point.y, accuracy: 0.001)
        }
    }

    func testTheSameRatioLandsOnTheSameSpotOnADifferentPhone() throws {
        let small = CoordinateMapper(viewSize: CGSize(width: 360, height: 640), frameSize: CGSize(width: 720, height: 1280))
        let large = CoordinateMapper(viewSize: CGSize(width: 800, height: 1280), frameSize: CGSize(width: 1600, height: 2560))
        let button = CGPoint(x: 0.85, y: 0.9)
        let a = try XCTUnwrap(small.touchPosition(forRatio: button))
        let b = try XCTUnwrap(large.touchPosition(forRatio: button))
        XCTAssertEqual(Double(a.x) / 719, 0.85, accuracy: 0.002)
        XCTAssertEqual(Double(b.x) / 1599, 0.85, accuracy: 0.002)
        XCTAssertEqual(Double(a.y) / 1279, Double(b.y) / 2559, accuracy: 0.002)
    }

    func testTouchPositionRoundTripsToTheSameRatio() throws {
        let mapper = CoordinateMapper(viewSize: CGSize(width: 540, height: 1170), frameSize: phone)
        let ratio = CGPoint(x: 0.25, y: 0.75)
        let position = try XCTUnwrap(mapper.touchPosition(forRatio: ratio))
        let back = mapper.ratio(for: position)
        XCTAssertEqual(back.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(back.y, 0.75, accuracy: 0.001)
    }

    func testDensityIndependentPixelsUseThePhonesRealScreenNotTheDownscaledFrame() throws {
        let info = try XCTUnwrap(DeviceInfoParser.parse("Physical size: 1080x2340\nPhysical density: 480"))
        let mapper = CoordinateMapper(viewSize: CGSize(width: 540, height: 1170), frameSize: CGSize(width: 540, height: 1170), device: info)
        let dp = try XCTUnwrap(mapper.dp(forRatio: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(dp.x, 180, accuracy: 0.001)
        XCTAssertEqual(dp.y, 390, accuracy: 0.001)
        let ratio = try XCTUnwrap(mapper.ratio(forDP: CGPoint(x: 90, y: 195)))
        XCTAssertEqual(ratio.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(mapper.dpSize(forRatioSize: CGSize(width: 1, height: 1))).width, 360, accuracy: 0.001)
    }

    func testLandscapeFramesUseTheRotatedScreen() throws {
        let info = try XCTUnwrap(DeviceInfoParser.parse("Physical size: 1080x2340\nPhysical density: 480"))
        let mapper = CoordinateMapper(viewSize: CGSize(width: 780, height: 360), frameSize: CGSize(width: 2340, height: 1080), device: info)
        XCTAssertEqual(try XCTUnwrap(mapper.dp(forRatio: CGPoint(x: 1, y: 1))).x, 780, accuracy: 0.001)
    }

    func testDegenerateSizesNeverProduceGarbage() {
        for mapper in [CoordinateMapper(viewSize: .zero, frameSize: CGSize(width: 1080, height: 2340)),
                       CoordinateMapper(viewSize: CGSize(width: 100, height: 100), frameSize: .zero),
                       CoordinateMapper(viewSize: CGSize(width: 100, height: 100), frameSize: CGSize(width: 70_000, height: 2340))] {
            XCTAssertNil(mapper.touchPosition(forViewPoint: CGPoint(x: 10, y: 10)))
        }
        XCTAssertNil(CoordinateMapper(viewSize: CGSize(width: 100, height: 100), frameSize: CGSize(width: 10, height: 10)).dp(forRatio: .zero),
                     "dp needs the screen size and density")
    }
}
