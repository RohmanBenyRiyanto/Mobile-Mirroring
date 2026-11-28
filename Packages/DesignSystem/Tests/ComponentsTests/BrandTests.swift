import SwiftUI
import TestSupport
import Theme
import XCTest
@testable import Components

final class SVGPathTests: XCTestCase {
    func testLinesAndHorizontalVerticalMoves() throws {
        let path = try XCTUnwrap(SVGPath.parse("M10 20 L110 20 V70 H10 Z"))
        XCTAssertEqual(path.boundingRect, CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    func testArcQuarterCircleStaysOnTheCircle() throws {
        let path = try XCTUnwrap(SVGPath.parse("M100 0 A100 100 0 0 1 0 100"))
        let bounds = path.cgPath.boundingBoxOfPath
        XCTAssertEqual(bounds.minX, 0, accuracy: 0.5)
        XCTAssertEqual(bounds.maxX, 100, accuracy: 0.5)
        XCTAssertEqual(bounds.maxY, 100, accuracy: 0.5)
        let middle = try XCTUnwrap(path.trimmedPath(from: 0, to: 0.5).currentPoint)
        XCTAssertEqual(hypot(middle.x, middle.y), 100, accuracy: 0.6, "a point halfway along the arc is 100 from the centre")
    }

    func testSweepFlagChoosesTheSide() throws {
        let a = try XCTUnwrap(SVGPath.parse("M0 0 A50 50 0 0 1 100 0")).boundingRect
        let b = try XCTUnwrap(SVGPath.parse("M0 0 A50 50 0 0 0 100 0")).boundingRect
        XCTAssertLessThan(a.minY, 0, "sweep 1 bulges one way")
        XCTAssertGreaterThan(b.maxY, 0, "sweep 0 bulges the other")
    }

    func testArcTooSmallForItsEndpointsIsScaledUp() throws {
        let path = try XCTUnwrap(SVGPath.parse("M0 0 A10 10 0 0 1 100 0"))
        XCTAssertEqual(path.boundingRect.width, 100, accuracy: 0.5)
    }

    func testMalformedDataIsRejected() {
        XCTAssertNil(SVGPath.parse("M10"))
        XCTAssertNil(SVGPath.parse("X 1 2"))
        XCTAssertNil(SVGPath.parse("M1 2 A5 5"))
    }
}

final class BrandMarkTests: XCTestCase {
    func testMarkMatchesTheSVGLayers() {
        let bounds = BrandMark.artworkBounds
        XCTAssertEqual(bounds.minX, 301.72 + 14 * 0.79327, accuracy: 1.5)
        XCTAssertEqual(bounds.maxX, 301.72 + 496 * 0.79327, accuracy: 1.5)
        XCTAssertEqual(bounds.minY, 168.51 + 21.5 * 0.79327, accuracy: 4)
        XCTAssertEqual(bounds.maxY, 168.51 + 846.1 * 0.79327, accuracy: 1.5)
        XCTAssertEqual(bounds.width / bounds.height, 382.0 / 654.0, accuracy: 0.01)
    }

    func testMarkIsCenteredOnTheIconCanvas() {
        let bounds = BrandMark.artworkBounds
        XCTAssertEqual(bounds.midX, 512, accuracy: 12)
        XCTAssertEqual(bounds.midY, 512, accuracy: 4)
    }

    func testMarkFitsAndCentersInAnyRect() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 100)
        let box = BrandMark().path(in: rect).boundingRect
        XCTAssertEqual(box.height, 100, accuracy: 0.5, "limited by the height")
        XCTAssertEqual(box.midX, 150, accuracy: 0.5)
        XCTAssertTrue(BrandMark().path(in: .zero).isEmpty)
    }

    func testEveryGlassLayerIsInThePackage() throws {
        for variant in BrandVariant.allCases {
            for piece in ["1-background", "2-shadow", "3-mark-glass", "3-mark-glass-left", "3-mark-glass-right"] {
                let name = "BrandGlass-\(variant.rawValue)-\(piece)"
                let image = try XCTUnwrap(Bundle.module.image(forResource: name), "\(name) is missing from the brand assets")
                XCTAssertEqual(image.representations.first?.pixelsWide, 1024, name)
            }
        }
    }

    func testTileVariantsUseTheDesignColours() {
        XCTAssertEqual(BrandTile.colors(.darkBlue).mark, .white)
        XCTAssertNotEqual(BrandTile.colors(.light).mark, .white)
        XCTAssertNotEqual(BrandTile.colors(.darkBlue).top, BrandTile.colors(.darkBlue).bottom)
    }

    @MainActor
    func testLogoAndTilesRenderInBothAppearances() throws {
        let gallery = HStack(spacing: 16) {
            BrandLogo(height: 80)
            BrandLogo(height: 80, style: .glass)
            BrandTile(size: 96, variant: .darkBlue)
            BrandTile(size: 96, variant: .clearBlue)
            BrandTile(size: 96, variant: .light)
            BrandTile(size: 96, variant: .darkBlue, style: .glass)
            BrandTile(size: 96, variant: .clearBlue, style: .glass)
            BrandTile(size: 96, variant: .light, style: .glass)
        }
        .padding(20)
        .background(Theme.Palette.window.color)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let image = try renderSnapshot(gallery, size: CGSize(width: 900, height: 140), name: "brand-\(appearance == .aqua ? "light" : "dark")", appearance: appearance)
            XCTAssertFalse(isBlankImage(image))
        }
    }
}

final class SurfaceRenderingTests: XCTestCase {
    override func tearDown() {
        SurfaceStyle.mode = .automatic
        SurfaceStyle.allowsGlass = true
        super.tearDown()
    }

    func testSolidAlwaysWins() {
        SurfaceStyle.mode = .solid
        XCTAssertEqual(SurfaceStyle.rendering, .solid)
        SurfaceStyle.allowsGlass = false
        XCTAssertEqual(SurfaceStyle.rendering, .solid)
    }

    func testOnAnOlderSystemAutomaticIsAMaterialAndGlassIsImitated() {
        SurfaceStyle.allowsGlass = false
        SurfaceStyle.mode = .automatic
        XCTAssertEqual(SurfaceStyle.rendering, .material)
        SurfaceStyle.mode = .glass
        XCTAssertEqual(SurfaceStyle.rendering, .emulatedGlass)
    }

    func testOnMacOS26RealGlassIsUsedUnlessSolidIsChosen() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("needs macOS 26") }
        SurfaceStyle.mode = .automatic
        XCTAssertEqual(SurfaceStyle.rendering, .realGlass)
        SurfaceStyle.mode = .glass
        XCTAssertEqual(SurfaceStyle.rendering, .realGlass)
    }

    @MainActor
    func testEveryRenderingDrawsSomething() throws {
        SurfaceStyle.allowsGlass = false
        for mode in SurfaceMode.allCases {
            SurfaceStyle.mode = mode
            let view = ZStack {
                LinearGradient(colors: [.blue, .teal], startPoint: .top, endPoint: .bottom)
                Text("Glass").padding(20).glassSurface(in: Capsule())
            }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let image = try renderSnapshot(view, size: CGSize(width: 220, height: 100), name: "surface-\(mode.rawValue)-\(appearance == .aqua ? "light" : "dark")", appearance: appearance)
                XCTAssertFalse(isBlankImage(image), "\(mode)")
            }
        }
    }
}
