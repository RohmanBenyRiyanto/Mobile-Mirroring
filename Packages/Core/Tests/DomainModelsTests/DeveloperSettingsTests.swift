import XCTest
@testable import DomainModels

final class DeveloperSettingsTests: XCTestCase {
    func testParsesRealOutputAndDefaultsForMissingValues() {
        let out = "##LAYOUT\n\n##OVERDRAW\n\n##FINISH\n0\n##ANIM\n1.0\n1.0\n1.0\n##NIGHT\nNight mode: yes\n"
        var expected = DeveloperState()
        expected.nightMode = .yes
        XCTAssertEqual(DeveloperSettings.parse(out), expected)

        let on = DeveloperSettings.parse("##LAYOUT\ntrue\n##OVERDRAW\nshow\n##FINISH\n1\n##ANIM\n0.5\n##NIGHT\nNight mode: auto\n")
        XCTAssertTrue(on.layoutBounds && on.gpuOverdraw && on.dontKeepActivities)
        XCTAssertEqual(on.animationScale, 0.5)
        XCTAssertEqual(on.nightMode, .auto)
    }

    func testNullSettingsFromAdbMeanDefault() {
        let s = DeveloperSettings.parse("##FINISH\nnull\n##ANIM\nnull\n")
        XCTAssertFalse(s.dontKeepActivities)
        XCTAssertEqual(s.animationScale, 1)
    }

    func testCommandsOnlyForWhatChanged() {
        let old = DeveloperState()
        XCTAssertTrue(DeveloperSettings.commands(from: old, to: old).isEmpty)
        var new = old
        new.layoutBounds = true
        new.animationScale = 0.5
        new.nightMode = .no
        let commands = DeveloperSettings.commands(from: old, to: new)
        XCTAssertEqual(commands.first, "setprop debug.layout true")
        XCTAssertEqual(commands.filter { $0.hasSuffix("scale 0.5") }.count, 3)
        XCTAssertEqual(commands.last, "cmd uimode night no")
    }

    func testRestoreCommandsMirrorTheChange() {
        var changed = DeveloperState()
        changed.gpuOverdraw = true
        changed.dontKeepActivities = true
        XCTAssertEqual(DeveloperSettings.commands(from: changed, to: DeveloperState()),
                       ["setprop debug.hwui.overdraw ''", "settings put global always_finish_activities 0"])
    }
}
