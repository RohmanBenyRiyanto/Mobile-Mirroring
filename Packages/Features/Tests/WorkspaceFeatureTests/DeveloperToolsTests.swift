import DomainModels
import XCTest
@testable import WorkspaceFeature

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    var commands: [String] { lock.lock(); defer { lock.unlock() }; return items }
    func add(_ c: String) { lock.lock(); items.append(c); lock.unlock() }
}

@MainActor
final class DeveloperToolsTests: XCTestCase {
    private func model(_ log: Log) -> DeveloperToolsModel {
        DeveloperToolsModel { command in
            log.add(command)
            return command.hasPrefix("echo") ? "##LAYOUT\n\n##FINISH\n0\n##ANIM\n1.0\n##NIGHT\nNight mode: yes\n" : ""
        }
    }

    func testChangeUndoAndResetAll() async {
        let log = Log()
        let tools = model(log)
        await tools.load()
        XCTAssertEqual(tools.state.nightMode, .yes)
        XCTAssertFalse(tools.hasChanges)

        tools.change { $0.layoutBounds = true }
        XCTAssertTrue(tools.state.layoutBounds)
        XCTAssertTrue(tools.hasChanges)
        XCTAssertTrue(tools.canUndo)

        tools.undo()
        XCTAssertFalse(tools.state.layoutBounds)
        XCTAssertFalse(tools.canUndo)

        tools.change { $0.dontKeepActivities = true; $0.nightMode = .no }
        tools.resetAll()
        XCTAssertEqual(tools.state.nightMode, .yes)
        XCTAssertFalse(tools.hasChanges)
        XCTAssertEqual(log.commands.last, "settings put global always_finish_activities 0; cmd uimode night yes")
    }

    func testRestoreOnEndOnlySendsWhenSomethingChanged() async {
        let log = Log()
        let tools = model(log)
        await tools.load()
        tools.restoreOnEnd()
        XCTAssertEqual(log.commands.count, 1)
        tools.change { $0.gpuOverdraw = true }
        tools.restoreOnEnd()
        XCTAssertEqual(log.commands.last, "setprop debug.hwui.overdraw ''")
    }
}
