import SwiftUI
import TestSupport
import XCTest
@testable import Theme

final class ThemeTests: XCTestCase {
    /// The design's own token file, kept in the repo as the reference the code must match.
    private func tokens() throws -> [String: Any] {
        // Walk up from this file to the project root, where docs/design/tokens.json lives.
        var folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.appendingPathComponent("docs/design/tokens.json").path), folder.path != "/" {
            folder.deleteLastPathComponent()
        }
        let data = try Data(contentsOf: folder.appendingPathComponent("docs/design/tokens.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func semantic(_ appearance: String) throws -> [String: Any] {
        let color = try XCTUnwrap(try tokens()["color"] as? [String: Any])
        let block = try XCTUnwrap(color[appearance] as? [String: Any])
        return try XCTUnwrap(block["semantic"] as? [String: Any])
    }

    // MARK: Hex

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

    // MARK: Tokens match the design file

    func testPaletteMatchesTheDesignFile() throws {
        let pairs: [(String, ThemeColor)] = [
            ("window", Theme.Palette.window), ("card", Theme.Palette.card), ("control", Theme.Palette.control),
            ("hover", Theme.Palette.hover), ("hairline", Theme.Palette.hairline), ("controlBorder", Theme.Palette.controlBorder),
            ("text", Theme.Palette.text), ("textSecondary", Theme.Palette.textSecondary), ("accentText", Theme.Palette.accentText),
        ]
        let light = try semantic("light"), dark = try semantic("dark")
        for (name, color) in pairs {
            XCTAssertEqual(color.light, light[name] as? String, "\(name) light")
            XCTAssertEqual(color.dark, dark[name] as? String, "\(name) dark")
        }
        let colors = try XCTUnwrap(try tokens()["color"] as? [String: Any])
        XCTAssertEqual(Theme.Palette.red.light, (colors["light"] as? [String: Any])?["red"] as? String)
        XCTAssertEqual(Theme.Palette.red.dark, (colors["dark"] as? [String: Any])?["red"] as? String)
        XCTAssertEqual(Theme.Palette.redFill.light, (colors["light"] as? [String: Any])?["redFill"] as? String)
    }

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

    // MARK: Accessibility the design promises

    func testTextOnSurfacesPasses4Point5() throws {
        for appearance in ["light", "dark"] {
            let surfaces = [Theme.Palette.window, Theme.Palette.card, Theme.Palette.control, Theme.Palette.hover]
            func value(_ c: ThemeColor) -> HexColor { appearance == "light" ? c.lightValue : c.darkValue }
            for surface in surfaces {
                for text in [Theme.Palette.text, Theme.Palette.textSecondary, Theme.Palette.accentText] {
                    // Secondary text and links sit on window and card; on hover/control only primary text is promised.
                    if text.light != Theme.Palette.text.light, surface.light == Theme.Palette.hover.light { continue }
                    XCTAssertGreaterThanOrEqual(HexColor.contrast(value(text), value(surface)), 4.5,
                                                "\(text.light)/\(text.dark) on \(surface.light)/\(surface.dark) (\(appearance))")
                }
            }
        }
    }

    func testControlBordersPass3Point1() {
        for surface in [Theme.Palette.window, Theme.Palette.card] {
            XCTAssertGreaterThanOrEqual(HexColor.contrast(Theme.Palette.controlBorder.lightValue, surface.lightValue), 3.1)
            XCTAssertGreaterThanOrEqual(HexColor.contrast(Theme.Palette.controlBorder.darkValue, surface.darkValue), 3.1)
        }
    }

    func testWhiteOnAccentAndOnRecordFill() throws {
        let white = try XCTUnwrap(HexColor("#ffffff"))
        // The design's Increase Contrast blue: the one it measured for white text.
        XCTAssertGreaterThanOrEqual(HexColor.contrast(white, try XCTUnwrap(HexColor("#1e6ef4"))), 4.5)
        // The default system blue is below, which is why code uses Color.accentColor and not a fixed value.
        XCTAssertLessThan(HexColor.contrast(white, try XCTUnwrap(HexColor("#0088ff"))), 4.5)
        XCTAssertGreaterThanOrEqual(HexColor.contrast(white, Theme.Palette.redFill.lightValue), 4.5)
    }

    func testRedTextPassesOnItsSurfaces() {
        XCTAssertGreaterThanOrEqual(HexColor.contrast(Theme.Palette.red.lightValue, Theme.Palette.card.lightValue), 4.5)
        XCTAssertGreaterThanOrEqual(HexColor.contrast(Theme.Palette.red.darkValue, Theme.Palette.card.darkValue), 4.5)
    }

    // MARK: Appearance and surfaces

    func testColourFollowsTheAppearance() throws {
        let color = Theme.Palette.window.nsColor
        var light = NSColor.clear, dark = NSColor.clear
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { light = color.usingColorSpace(.sRGB)! }
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance { dark = color.usingColorSpace(.sRGB)! }
        XCTAssertNotEqual(light, dark)
        XCTAssertEqual(light.redComponent, 245.0 / 255, accuracy: 0.002)
        XCTAssertEqual(dark.redComponent, 28.0 / 255, accuracy: 0.002)
    }

    @MainActor
    func testSurfacesRenderInBothAppearances() throws {
        let view = ZStack {
            Theme.Palette.window.color
            VStack(spacing: 12) {
                Text("Glass surface").padding(16).glassSurface(in: Capsule())
                Button("Start Mirroring") {}.prominentAction()
                Button("Cancel") {}.secondaryAction()
                Text("12.3 fps").padding(8).overVideo(in: RoundedRectangle(cornerRadius: 8))
                Text("Card").padding(16).card()
            }
        }
        // Real glass does not draw off screen, so the look older systems get is the one that can be checked here.
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let image = try renderSnapshot(view, size: CGSize(width: 320, height: 300), name: "theme-\(appearance == .aqua ? "light" : "dark")", appearance: appearance)
            XCTAssertFalse(isBlankImage(image))
        }
    }
}
