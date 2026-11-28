import SwiftUI
import TestSupport
import XCTest
@testable import Theme

final class ThemeTests: XCTestCase {
    private func tokens() throws -> [String: Any] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/tokens.json")
        let data = try Data(contentsOf: file)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Hex and contrast maths

    func testHexParsing() throws {
        let color = try XCTUnwrap(HexColor("#1e6ef4"))
        XCTAssertEqual(color.red, 30.0 / 255, accuracy: 1e-9)
        XCTAssertNotNil(HexColor("ffffff"))
        XCTAssertNil(HexColor("#fff"))
        XCTAssertNil(HexColor("#gggggg"))
        XCTAssertNil(HexColor(""))
    }

    func testContrastRatioMatchesKnownValues() throws {
        let black = try XCTUnwrap(HexColor("#000000")), white = try XCTUnwrap(HexColor("#ffffff"))
        XCTAssertEqual(HexColor.contrast(black, white), 21, accuracy: 0.001)
        XCTAssertEqual(HexColor.contrast(white, white), 1, accuracy: 0.001)
    }

    // MARK: Layout matches the design file

    func testLayoutMatchesTheDesignFile() throws {
        let file = try tokens()
        let spacing = try XCTUnwrap(file["spacing"] as? [String: Double])
        XCTAssertEqual(spacing["inset"], Double(Theme.Space.inset))
        XCTAssertEqual(spacing["1"], Double(Theme.Space.s1))
        XCTAssertEqual(spacing["4"], Double(Theme.Space.s4))
        XCTAssertEqual(spacing["12"], Double(Theme.Space.s12))
        let radius = try XCTUnwrap(file["radius"] as? [String: Any])
        XCTAssertEqual(radius["field"] as? Double, Double(Theme.Radius.field))
        XCTAssertEqual(radius["card"] as? Double, Double(Theme.Radius.card))
        XCTAssertEqual(radius["window"] as? Double, Double(Theme.Radius.window))
        XCTAssertEqual(radius["sheet"] as? Double, Double(Theme.Radius.sheet))
        XCTAssertEqual(radius["rail"] as? Double, Double(Theme.Radius.rail))
        let size = try XCTUnwrap(file["size"] as? [String: Any])
        XCTAssertEqual(size["connectWindow"] as? [Double], [Double(Theme.Size.connectWindow.width), Double(Theme.Size.connectWindow.height)])
        XCTAssertEqual(size["connectMinimum"] as? [Double], [Double(Theme.Size.connectMinimum.width), Double(Theme.Size.connectMinimum.height)])
        XCTAssertEqual(size["sidebar"] as? Double, Double(Theme.Size.sidebar))
        XCTAssertEqual(size["rail"] as? Double, Double(Theme.Size.rail))
    }

    // MARK: Colours are the system's

    private let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private func rgba(_ color: NSColor) -> (r: Double, g: Double, b: Double, a: Double) {
        let c = color.usingColorSpace(.sRGB) ?? color
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    private func composite(_ top: ThemeColor, over background: ThemeColor, in appearance: NSAppearance.Name) -> HexColor {
        let (t, b) = (rgba(top.resolved(in: appearance)), rgba(background.resolved(in: appearance)))
        func mix(_ x: Double, _ y: Double) -> Double { x * t.a + y * (1 - t.a) }
        return HexColor(red: mix(t.r, b.r), green: mix(t.g, b.g), blue: mix(t.b, b.b))
    }

    private func luminance(_ color: ThemeColor, over background: ThemeColor, in appearance: NSAppearance.Name) -> Double {
        composite(color, over: background, in: appearance).luminance
    }

    func testPaletteIsMadeOfTheSystemsOwnColours() {
        let pairs: [(String, ThemeColor, NSColor)] = [
            ("text", Theme.Palette.text, .labelColor), ("textSecondary", Theme.Palette.textSecondary, .secondaryLabelColor),
            ("hairline", Theme.Palette.hairline, .separatorColor), ("page", Theme.Palette.page, .underPageBackgroundColor),
            ("window", Theme.Palette.window, .windowBackgroundColor), ("accentText", Theme.Palette.accentText, .controlAccentColor),
            ("red", Theme.Palette.red, .systemRed), ("control", Theme.Palette.control, .secondarySystemFill),
        ]
        for (name, ours, system) in pairs {
            for appearance in appearances {
                var expected = system
                NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance { expected = system.usingColorSpace(.sRGB) ?? system }
                let (a, b) = (rgba(ours.resolved(in: appearance)), rgba(expected))
                XCTAssertEqual(a.r, b.r, accuracy: 0.004, "\(name) \(appearance.rawValue)")
                XCTAssertEqual(a.g, b.g, accuracy: 0.004, "\(name) \(appearance.rawValue)")
                XCTAssertEqual(a.b, b.b, accuracy: 0.004, "\(name) \(appearance.rawValue)")
                XCTAssertEqual(a.a, b.a, accuracy: 0.004, "\(name) \(appearance.rawValue)")
            }
        }
    }

    func testColoursFollowTheAppearance() {
        let light = rgba(Theme.Palette.text.resolved(in: .aqua)), dark = rgba(Theme.Palette.text.resolved(in: .darkAqua))
        XCTAssertLessThan(light.r, 0.3, "dark text in light mode")
        XCTAssertGreaterThan(dark.r, 0.7, "light text in dark mode")
        XCTAssertLessThan(luminance(Theme.Palette.page, over: Theme.Palette.window, in: .darkAqua),
                          luminance(Theme.Palette.page, over: Theme.Palette.window, in: .aqua), "the page is darker in dark mode")
    }

    func testACardIsLighterThanThePageInBothAppearancesWithoutNeedingABorder() {
        for appearance in appearances {
            let page = luminance(Theme.Palette.page, over: Theme.Palette.window, in: appearance)
            let card = luminance(Theme.Palette.card, over: Theme.Palette.page, in: appearance)
            XCTAssertGreaterThan(card, page, "card must lift off the page (\(appearance.rawValue))")
        }
    }

    func testTextIsReadableOnThePageAndOnACard() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "System colours differ between macOS releases, so the contrast is only measured on a developer's Mac")
        for appearance in appearances {
            for surface in [Theme.Palette.page, Theme.Palette.card] {
                let background = composite(surface, over: Theme.Palette.page, in: appearance)
                let primary = composite(Theme.Palette.text, over: surface, in: appearance)
                XCTAssertGreaterThanOrEqual(HexColor.contrast(primary, background), 7, "primary text, \(appearance.rawValue)")
                let secondary = composite(Theme.Palette.textSecondary, over: surface, in: appearance)
                XCTAssertGreaterThanOrEqual(HexColor.contrast(secondary, background), 3, "secondary text, \(appearance.rawValue)")
            }
        }
    }

    func testSeparatorsAreFaint() {
        for appearance in appearances {
            XCTAssertLessThanOrEqual(rgba(Theme.Palette.hairline.resolved(in: appearance)).a, 0.15, "a line, not a wall (\(appearance.rawValue))")
        }
    }

    func testBrandColourStillTakesTwoHexValues() {
        let brand = ThemeColor(light: "#ffffff", dark: "#000000")
        XCTAssertEqual(rgba(brand.resolved(in: .aqua)).r, 1, accuracy: 0.01)
        XCTAssertEqual(rgba(brand.resolved(in: .darkAqua)).r, 0, accuracy: 0.01)
    }

    // MARK: Surfaces

    @MainActor
    func testSurfacesRenderInBothAppearances() throws {
        let view = ZStack {
            Theme.Palette.page.color
            VStack(spacing: 12) {
                Text("Glass surface").padding(16).glassSurface(in: Capsule())
                Button("Start Mirroring") {}.prominentAction()
                Button("Cancel") {}.secondaryAction()
                Text("12.3 fps").padding(8).overVideo(in: RoundedRectangle(cornerRadius: 8))
                Text("Card").padding(16).card()
            }
        }
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        for appearance in appearances {
            let image = try renderSnapshot(view, size: CGSize(width: 320, height: 300), name: "theme-\(appearance == .aqua ? "light" : "dark")", appearance: appearance)
            XCTAssertFalse(isBlankImage(image))
        }
    }
}
