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

final class RailLayoutTests: XCTestCase {
    func testTheStandardLayoutHasADistinctListPerMode() {
        let standard = RailLayout.standard
        XCTAssertTrue(standard.isStandard)
        XCTAssertEqual(Set(WorkspaceMode.allCases.map { standard.items(for: $0) }).count, 3)
        for mode in WorkspaceMode.allCases {
            let items = standard.items(for: mode)
            XCTAssertEqual(items.count, Set(items).count, "\(mode) lists a tool twice")
        }
    }

    func testALineIsDrawnWhereTheGroupChanges() {
        let rows = RailLayout(lists: [.normal: [.back, .home, .volumeUp, .power, .screenshot]]).rows(for: .normal)
        XCTAssertEqual(rows, [.item(.back), .item(.home), .separator, .item(.volumeUp), .item(.power), .separator, .item(.screenshot)])
    }

    func testAddingPutsAToolNextToItsGroupAndNeverTwice() {
        var layout = RailLayout.standard
        layout.remove(.mute, from: .normal)
        XCTAssertFalse(layout.items(for: .normal).contains(.mute))
        layout.add(.mute, to: .normal)
        let items = layout.items(for: .normal)
        XCTAssertEqual(items.firstIndex(of: .mute), items.firstIndex(of: .record).map { $0 + 1 })
        layout.add(.mute, to: .normal)
        XCTAssertEqual(layout.items(for: .normal).filter { $0 == .mute }.count, 1)
        layout.add(.logcat, to: .normal)
        XCTAssertEqual(layout.items(for: .normal).last, .logcat, "a tool with no group mate goes last")
    }

    func testMovingStaysInsideTheList() {
        var layout = RailLayout(lists: [.normal: [.back, .home, .recents]])
        layout.move(.back, by: -1, in: .normal)
        XCTAssertEqual(layout.items(for: .normal), [.back, .home, .recents])
        layout.move(.back, by: 1, in: .normal)
        XCTAssertEqual(layout.items(for: .normal), [.home, .back, .recents])
        layout.move(fromOffsets: IndexSet(integer: 2), toOffset: 0, in: .normal)
        XCTAssertEqual(layout.items(for: .normal), [.recents, .home, .back])
    }

    func testChangesToOneModeLeaveTheOthersAlone() {
        var layout = RailLayout.standard
        layout.remove(.back, from: .gaming)
        XCTAssertTrue(layout.items(for: .normal).contains(.back))
        XCTAssertFalse(layout.isStandard)
        layout.reset(.gaming)
        XCTAssertTrue(layout.isStandard)
        layout.remove(.home, from: .normal)
        layout.remove(.home, from: .developer)
        layout = .standard
        XCTAssertTrue(layout.isStandard)
    }

    func testHiddenToolsAreTheOnesNotShown() {
        let layout = RailLayout(lists: [.normal: [.back]])
        XCTAssertEqual(layout.hidden(in: .normal).count, RailItemID.allCases.count - 1)
        XCTAssertFalse(layout.hidden(in: .normal).contains(.back))
    }

    func testSavedLayoutsRoundTripAndTolerateUnknownOrMissingData() throws {
        var layout = RailLayout.standard
        layout.remove(.mute, from: .normal)
        layout.move(.statistics, by: -1, in: .normal)
        XCTAssertEqual(RailLayout.decode(try JSONEncoder().encode(layout)), layout)

        let future = Data(#"{"lists":{"normal":["back","teleport","back","home"],"gaming":["nonsense"]}}"#.utf8)
        let decoded = try XCTUnwrap(RailLayout.decode(future))
        XCTAssertEqual(decoded.items(for: .normal), [.back, .home], "unknown tools are dropped and repeats removed")
        XCTAssertEqual(decoded.items(for: .gaming), [], "a list of only unknown tools is empty, not the default")
        XCTAssertEqual(decoded.items(for: .developer), RailLayout.defaultItems(for: .developer), "a missing mode gets its standard list")
    }

    func testGarbageAndOversizedDataAreIgnored() {
        XCTAssertNil(RailLayout.decode(Data("not json".utf8)))
        XCTAssertNil(RailLayout.decode(Data(count: RailLayout.maxSavedBytes + 1)))
        XCTAssertNotNil(RailLayout.decode(Data("{}".utf8)), "an empty object is a layout that falls back to the standard lists")
    }

    @MainActor
    func testTheLayoutIsRememberedByTheModel() {
        let defaults = isolatedDefaults()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = AppModel(keymapRoot: root, defaults: defaults)
        first.railLayout.remove(.power, from: .normal)
        let second = AppModel(keymapRoot: root, defaults: defaults)
        XCTAssertFalse(second.railLayout.items(for: .normal).contains(.power))
    }

    @MainActor
    func testTheRailDrawsWhatTheLayoutSays() throws {
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        let app = AppModel(keymapRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: isolatedDefaults())
        app.railLayout = RailLayout(lists: [.normal: []])
        let empty = try renderSnapshot(RailView(model: app, isCollapsed: .constant(false)), size: CGSize(width: 100, height: 200), name: "rail-empty")
        XCTAssertFalse(isBlankImage(empty), "Disconnect and the hide button stay even with nothing else")
    }
}
