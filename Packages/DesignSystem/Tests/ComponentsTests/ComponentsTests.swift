import SwiftUI
import TestSupport
import Theme
import XCTest
@testable import Components

@MainActor
final class ComponentsTests: XCTestCase {
    private var gallery: some View {
        GroupedForm {
            SettingsCard("Quality") {
                PlainRow {
                    HStack {
                        PresetCard("Balanced", detail: "1920 px · 60 fps · 8 Mbps", isSelected: false) {}
                        PresetCard("Game streaming", detail: "Native · 60 fps · steady 40 Mbps", isSelected: true) {}
                    }
                }
            }
            SettingsCard("OBS") {
                SettingsRow("Audio", detail: "Play phone sound on this Mac") { Toggle("", isOn: .constant(true)).labelsHidden() }
                SettingsRow("Port") { Text("8765").font(Theme.Font.mono) }
                MonoField("http://127.0.0.1:8765/live.ts") { Button("Copy") {} }
                NumberedSteps(["In OBS, add a Media Source.", "Untick Local File and paste the address.", "Set Network Buffering to 0 MB."])
            }
        }
    }

    func testGalleryRendersInBothAppearances() throws {
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let image = try renderSnapshot(gallery, size: CGSize(width: 520, height: 520),
                                           name: "components-\(appearance == .aqua ? "light" : "dark")", appearance: appearance)
            XCTAssertFalse(isBlankImage(image))
        }
    }

    func testPresetCardReportsItsSelectionToAssistiveTechnology() {
        _ = PresetCard("A", detail: "x", isSelected: true) {}
        _ = PresetCard("B", detail: "y", isSelected: false) {}
    }
}
