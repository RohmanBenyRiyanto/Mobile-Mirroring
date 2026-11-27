import AppKit
import SwiftUI
import XCTest
import TestSupport
@testable import DomainModels
@testable import InspectorFeature

final class DesignTests: XCTestCase {
    /// A PNG whose left half is pure red and right half pure blue, 10×20 pixels.
    private func twoColorPNG() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 10, pixelsHigh: 20, bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<20 { for x in 0..<10 {
            rep.setColor(x < 5 ? NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1) : NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: x, y: y)
        } }
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    // MARK: Grid

    func testGridLinesAreEveryStepInDP() {
        // 1080 px wide at 2.5 (400 dpi) = 432 dp. An 8 dp step is 20 px.
        let lines = DesignGrid.lines(extentPixels: 1080, densityScale: 2.5, stepDP: 8, viewLength: 432)
        XCTAssertEqual(lines.count, 53) // 8, 16 … 424 (432 itself is the edge)
        XCTAssertEqual(lines[0].ratio, 20.0 / 1080, accuracy: 1e-9)
        XCTAssertFalse(lines[0].isMajor)
        XCTAssertTrue(lines[3].isMajor) // every 4th: 32 dp
        XCTAssertEqual(lines[3].ratio, 80.0 / 1080, accuracy: 1e-9)
    }

    func testGridHidesWhenLinesWouldBlur() {
        XCTAssertTrue(DesignGrid.lines(extentPixels: 1080, densityScale: 2.5, stepDP: 4, viewLength: 100).isEmpty)
        XCTAssertFalse(DesignGrid.lines(extentPixels: 1080, densityScale: 2.5, stepDP: 4, viewLength: 600).isEmpty)
    }

    func testGridRejectsNonsenseInput() {
        XCTAssertTrue(DesignGrid.lines(extentPixels: 0, densityScale: 2.5, stepDP: 8, viewLength: 400).isEmpty)
        XCTAssertTrue(DesignGrid.lines(extentPixels: 1080, densityScale: 0, stepDP: 8, viewLength: 400).isEmpty)
        XCTAssertTrue(DesignGrid.lines(extentPixels: 1080, densityScale: 2.5, stepDP: 0, viewLength: 400).isEmpty)
    }

    func testGridOptions() {
        XCTAssertNil(DesignGrid.off.stepDP)
        XCTAssertEqual(DesignGrid.dp4.stepDP, 4)
        XCTAssertEqual(DesignGrid.dp8.title, "8 dp Grid")
    }

    // MARK: Crosshair

    func testCrosshairReadout() throws {
        let readout = try XCTUnwrap(CrosshairReadout(ratio: CGPoint(x: 0.5, y: 0.25), screenSize: CGSize(width: 1080, height: 2340), densityScale: 2.5))
        XCTAssertEqual(readout.pixelText, "540, 585 px")
        XCTAssertEqual(readout.dpText, "216, 234 dp")
        XCTAssertEqual(readout.rightPixels, 539)
        XCTAssertEqual(readout.bottomPixels, 1754)
    }

    func testCrosshairAtTheEdgesStaysOnScreen() throws {
        let corner = try XCTUnwrap(CrosshairReadout(ratio: CGPoint(x: 1, y: 1), screenSize: CGSize(width: 1080, height: 2340), densityScale: nil))
        XCTAssertEqual(corner.pixelText, "1079, 2339 px")
        XCTAssertEqual(corner.rightPixels, 0)
        XCTAssertNil(corner.dpText)
        XCTAssertNil(CrosshairReadout(ratio: CGPoint(x: 1.1, y: 0.5), screenSize: CGSize(width: 10, height: 10), densityScale: 1))
        XCTAssertNil(CrosshairReadout(ratio: CGPoint(x: 0.5, y: 0.5), screenSize: .zero, densityScale: 1))
    }

    // MARK: Colours

    func testReadsExactPixelColours() throws {
        let image = try XCTUnwrap(PixelImage(png: try twoColorPNG()))
        XCTAssertEqual(image.width, 10)
        XCTAssertEqual(image.height, 20)
        let red = try XCTUnwrap(image.color(atRatio: CGPoint(x: 0.1, y: 0.5)))
        XCTAssertEqual(red.hex, "#FF0000")
        XCTAssertEqual(red.rgbText, "rgb(255, 0, 0)")
        XCTAssertEqual(image.color(atRatio: CGPoint(x: 0.9, y: 0.5))?.hex, "#0000FF")
        XCTAssertEqual(image.color(atRatio: CGPoint(x: 1, y: 1))?.x, 9) // the far edge is the last pixel, not past it
        XCTAssertNil(image.color(atRatio: CGPoint(x: 1.01, y: 0.5)))
        XCTAssertNil(image.color(atRatio: CGPoint(x: -0.1, y: 0.5)))
    }

    func testRejectsPicturesThatAreNotImages() {
        XCTAssertNil(PixelImage(png: Data("not a png".utf8)))
        XCTAssertNil(PixelImage(png: Data()))
    }

    // MARK: Model

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { XCTFail("Timed out"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    func testColourPickerTakesAStillAndCopiesTheColour() async throws {
        let png = try twoColorPNG()
        let design = DesignModel(fetchScreenshot: { png })
        XCTAssertFalse(design.capturesPointer)
        design.setTool(.colorPicker)
        XCTAssertTrue(design.capturesPointer)
        try await waitUntil { design.snapshotStatus == .ready }

        design.pointerMoved(to: CGPoint(x: 0.9, y: 0.5))
        XCTAssertEqual(design.color?.hex, "#0000FF")
        XCTAssertEqual(design.copyColor(), "#0000FF")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "#0000FF")

        design.pointerMoved(to: nil)
        XCTAssertNil(design.copyColor())

        design.setTool(.off)
        XCTAssertNil(design.snapshot)
        XCTAssertEqual(design.snapshotStatus, .none)
    }

    @MainActor
    func testCrosshairNeedsNoScreenshot() {
        var fetches = 0
        let design = DesignModel(fetchScreenshot: { fetches += 1; return Data() })
        design.setTool(.crosshair)
        XCTAssertTrue(design.capturesPointer)
        XCTAssertEqual(fetches, 0)
        design.pointerMoved(to: CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(design.copyColor()) // only the colour picker copies
    }

    @MainActor
    func testFailedScreenshotIsReported() async throws {
        struct Boom: Error {}
        let design = DesignModel(fetchScreenshot: { throw Boom() })
        design.setTool(.colorPicker)
        try await waitUntil { if case .failed = design.snapshotStatus { return true } else { return false } }
        let garbage = DesignModel(fetchScreenshot: { Data("x".utf8) })
        garbage.setTool(.colorPicker)
        try await waitUntil { if case .failed = garbage.snapshotStatus { return true } else { return false } }
    }

    @MainActor
    func testSwitchingOffWhileReadingIgnoresTheLateAnswer() async throws {
        let png = try twoColorPNG()
        let design = DesignModel(fetchScreenshot: { try await Task.sleep(for: .milliseconds(150)); return png })
        design.setTool(.colorPicker)
        design.setTool(.off)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(design.snapshot)
        XCTAssertEqual(design.snapshotStatus, .none)
    }

    @MainActor
    func testResetTurnsEverythingOff() {
        let design = DesignModel(fetchScreenshot: { Data() })
        design.grid = .dp8
        design.setTool(.crosshair)
        design.reset()
        XCTAssertEqual(design.grid, .off)
        XCTAssertEqual(design.tool, .off)
    }

    // MARK: Drawing

    @MainActor
    func testOverlayDrawsGridCrosshairAndColour() async throws {
        let png = try twoColorPNG()
        let design = DesignModel(fetchScreenshot: { png })
        design.grid = .dp8
        design.setTool(.colorPicker)
        try await waitUntil { design.snapshotStatus == .ready }
        design.pointerMoved(to: CGPoint(x: 0.3, y: 0.7))
        let view = ZStack {
            Color.gray.opacity(0.3)
            DesignOverlay(design: design, videoSize: CGSize(width: 1080, height: 2340), screenSize: CGSize(width: 1080, height: 2340), densityScale: 2.5)
        }
        let image = try renderSnapshot(view, size: CGSize(width: 300, height: 650), name: "design")
        XCTAssertFalse(isBlankImage(image))
    }
}
