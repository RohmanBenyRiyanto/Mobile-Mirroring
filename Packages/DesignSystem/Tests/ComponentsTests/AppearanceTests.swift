import SwiftUI
import Theme
import XCTest
@testable import Components

@MainActor
final class AppearanceTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "benzmirror.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testEverythingFollowsTheSystemByDefault() {
        let store = AppearanceStore(defaults: defaults(), apply: { _ in })
        XCTAssertEqual(store.settings, AppearanceSettings())
        XCTAssertEqual(store.settings.mode, .system)
        XCTAssertEqual(store.settings.accent, .system)
        XCTAssertEqual(store.settings.surface, .automatic)
        XCTAssertEqual(store.settings.dockIcon, .standard)
        XCTAssertNil(store.settings.accentColor, "no accent is forced")
        XCTAssertNil(store.settings.colorScheme, "no appearance is forced")
    }

    func testChoicesAreRememberedAndApplied() {
        let suite = defaults()
        var applied: [AppearanceSettings] = []
        let store = AppearanceStore(defaults: suite, apply: { applied.append($0) })
        XCTAssertEqual(applied.count, 1, "the saved choice is applied once at launch")

        store.settings.mode = .dark
        store.settings.accent = .benzBlue
        store.settings.surface = .glass
        store.settings.dockIcon = .clearBlue
        XCTAssertEqual(applied.count, 5)
        XCTAssertEqual(applied.last, AppearanceSettings(mode: .dark, accent: .benzBlue, surface: .glass, dockIcon: .clearBlue))

        let again = AppearanceStore(defaults: suite, apply: { _ in })
        XCTAssertEqual(again.settings, store.settings, "a new launch starts where the last one ended")
    }

    func testSettingTheSameValueAgainDoesNothing() {
        var count = 0
        let store = AppearanceStore(defaults: defaults(), apply: { _ in count += 1 })
        store.settings.mode = .system
        XCTAssertEqual(count, 1)
    }

    func testResetFollowsTheSystemAgain() {
        let store = AppearanceStore(defaults: defaults(), apply: { _ in })
        store.settings = AppearanceSettings(mode: .light, accent: .benzBlue, surface: .solid, dockIcon: .darkBlue)
        store.reset()
        XCTAssertEqual(store.settings, AppearanceSettings())
    }

    func testBrandAccentAndSchemes() {
        XCTAssertNotNil(AppearanceSettings(accent: .benzBlue).accentColor)
        XCTAssertEqual(AppearanceSettings(mode: .dark).colorScheme, .dark)
        XCTAssertEqual(AppearanceSettings(mode: .light).colorScheme, .light)
    }

    func testOldOrUnknownSavedValuesFallBackToTheDefaults() throws {
        let partial = Data(#"{"mode":"dark"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppearanceSettings.self, from: partial)
        XCTAssertEqual(decoded.mode, .dark)
        XCTAssertEqual(decoded.accent, .system)

        let unknown = Data(#"{"mode":"sepia","surface":"holographic","dockIcon":"gold"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppearanceSettings.self, from: unknown), AppearanceSettings())
    }

    func testDockIconsMapToBrandVariants() {
        XCTAssertNil(AppearanceSettings.DockIcon.standard.brandVariant)
        XCTAssertEqual(AppearanceSettings.DockIcon.darkBlue.brandVariant, .darkBlue)
        XCTAssertEqual(AppearanceSettings.DockIcon.light.brandVariant, .light)
        XCTAssertNil(AppearanceStore.dockImage(for: .standard))
    }

    func testGlassDockIconIsRendered() throws {
        let image = try XCTUnwrap(AppearanceStore.dockImage(for: .darkBlue), "the glass render of the icon")
        XCTAssertGreaterThanOrEqual(image.size.width, 512)
    }
}
