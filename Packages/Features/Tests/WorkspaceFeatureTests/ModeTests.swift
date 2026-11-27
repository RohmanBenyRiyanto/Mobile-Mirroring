import DomainModels
import SwiftUI
import TestSupport
import Theme
import XCTest
@testable import WorkspaceFeature

final class ModeAutoSwitchTests: XCTestCase {
    func testAGameWithAKeymapSendsTheWindowToGamingAndBack() {
        var state = ModeAutoSwitch(mode: .developer)
        state = state.keymapTurnedOnAutomatically(enabled: true)
        XCTAssertEqual(state.mode, .gaming)
        XCTAssertEqual(state.restoreTo, .developer)
        state = state.keymapTurnedOffAutomatically()
        XCTAssertEqual(state.mode, .developer, "back to where the user was")
        XCTAssertNil(state.restoreTo)
    }

    func testNothingChangesWhenTheSettingIsOff() {
        let state = ModeAutoSwitch(mode: .normal).keymapTurnedOnAutomatically(enabled: false)
        XCTAssertEqual(state, ModeAutoSwitch(mode: .normal))
    }

    func testAModeTheUserChoseIsNeverTakenAway() {
        // Entered Gaming automatically, then the user chose Developer by hand: closing the game must not move them.
        var state = ModeAutoSwitch(mode: .normal).keymapTurnedOnAutomatically(enabled: true)
        state = state.chosen(.developer)
        XCTAssertNil(state.restoreTo)
        XCTAssertEqual(state.keymapTurnedOffAutomatically().mode, .developer)
        // Already in Gaming by hand: opening a game changes nothing and closing it does not leave Gaming.
        let manual = ModeAutoSwitch(mode: .gaming)
        XCTAssertEqual(manual.keymapTurnedOnAutomatically(enabled: true), manual)
        XCTAssertEqual(manual.keymapTurnedOffAutomatically().mode, .gaming)
    }

    func testModesHaveNamesSymbolsAndShortcuts() {
        XCTAssertEqual(WorkspaceMode.allCases, [.normal, .gaming, .developer])
        XCTAssertEqual(WorkspaceMode.allCases.map(\.shortcutKey), ["1", "2", "3"])
        XCTAssertEqual(Set(WorkspaceMode.allCases.map(\.symbol)).count, 3)
    }

    func testAutoGamingIsOffByDefaultAndOldSettingsStillLoad() throws {
        XCTAssertFalse(MirrorSettings().autoGamingMode)
        let old = try JSONDecoder().decode(MirrorSettings.self, from: Data(#"{"audioEnabled":true}"#.utf8))
        XCTAssertFalse(old.autoGamingMode)
    }
}

@MainActor
final class WorkspaceModeModelTests: XCTestCase {
    private func model(_ defaults: UserDefaults) -> AppModel {
        AppModel(keymapRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: defaults)
    }

    func testTheChosenModeIsRememberedForTheNextLaunch() {
        let defaults = isolatedDefaults()
        let first = model(defaults)
        XCTAssertEqual(first.mode, .normal, "manual: the first mode is Normal")
        first.setMode(.gaming)
        XCTAssertEqual(first.mode, .gaming)
        XCTAssertEqual(model(defaults).mode, .gaming)
    }

    func testEscapeLeavesStreamModeFirstAndOtherwiseBelongsToThePhone() {
        let app = model(isolatedDefaults())
        XCTAssertFalse(app.handleEscape(), "nothing open: Esc goes to the phone")
        app.isStreamMode = true
        XCTAssertTrue(app.handleEscape())
        XCTAssertFalse(app.isStreamMode)
        XCTAssertFalse(app.handleEscape())
    }

    func testGridCyclesOffFourEightOff() {
        XCTAssertEqual(RailView.nextGrid(after: .off), .dp4)
        XCTAssertEqual(RailView.nextGrid(after: .dp4), .dp8)
        XCTAssertEqual(RailView.nextGrid(after: .dp8), .off)
    }

    func testRailRendersForEveryModeAndWhenCollapsed() throws {
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        for mode in WorkspaceMode.allCases {
            let app = model(isolatedDefaults())
            app.setMode(mode)
            let image = try renderSnapshot(RailView(model: app, isCollapsed: .constant(false)), size: CGSize(width: 100, height: 860), name: "rail-\(mode.rawValue)")
            XCTAssertFalse(isBlankImage(image), mode.rawValue)
        }
        let collapsed = try renderSnapshot(RailView(model: model(isolatedDefaults()), isCollapsed: .constant(true)), size: CGSize(width: 100, height: 140), name: "rail-collapsed2")
        XCTAssertFalse(isBlankImage(collapsed))
    }
}

@MainActor
final class QuitGuardTests: XCTestCase {
    func testQuittingIsImmediateWhenNothingIsRecording() async {
        let app = AppModel(keymapRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: isolatedDefaults())
        var asked = false
        app.confirmQuitWhileRecording = { asked = true; return true }
        XCTAssertFalse(app.isAnyRecording)
        let proceed = await app.prepareToQuit()
        XCTAssertTrue(proceed)
        XCTAssertFalse(asked, "no dialog when there is nothing to lose")
    }
}
