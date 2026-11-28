import SwiftUI
import XCTest
import TestSupport
@testable import DomainModels
@testable import LogcatFeature

private enum Real {
    static let lines = [
        "11-27 16:22:43.880  2651  2651 D AndroidRuntime: Shutting down VM",
        "--------- beginning of crash",
        "11-27 16:22:43.882  2651  2651 E AndroidRuntime: FATAL EXCEPTION: main",
        "11-27 16:22:43.882  2651  2651 E AndroidRuntime: Process: com.android.settings, PID: 2651",
        "11-27 16:22:43.882  2651  2651 E AndroidRuntime: android.app.RemoteServiceException$CrashedByAdbException: shell-induced crash",
        "11-27 16:22:43.882  2651  2651 E AndroidRuntime: \tat android.app.ActivityThread.throwRemoteServiceException(ActivityThread.java:2872)",
        "11-27 16:22:43.882  2651  2651 E AndroidRuntime: \tat android.os.Looper.loop(Looper.java:422)",
        "11-27 16:22:43.882  2651  2651 E AndroidRuntime: \tat com.android.internal.os.ZygoteInit.main(ZygoteInit.java:982)",
        "11-27 16:22:43.901  3024 17379 I DropBoxManagerService: add tag=system_app_crash isTagEnabled=true flags=0x2",
        "11-27 16:22:44.029  3024  4946 I ActivityManager: Process com.android.settings (pid 2651) has died: fg  TOP (324,1726)",
    ]

    static let processList = """
      PID NAME
        1 init
        2 [kthreadd]
     2651 com.android.settings
     2700 com.android.settings:remote
     4888 com.sec.android.app.launcher
    28169 com.android.settings.intelligence
    """
}

private func line(_ pid: Int, _ tag: String, _ message: String, level: Character = "I", tid: Int? = nil) -> String {
    let paddedTag = tag + String(repeating: " ", count: max(0, 8 - tag.count))
    return "11-27 16:30:00.000 \(String(format: "%5d", pid)) \(String(format: "%5d", tid ?? pid)) \(level) \(paddedTag): \(message)"
}

final class LogEntryParsingTests: XCTestCase {
    func testTheFieldsOfARealLineAreRead() throws {
        let entry = LogEntry.parse(Real.lines[2], id: 7)
        XCTAssertEqual(entry.id, 7)
        XCTAssertEqual(entry.pid, 2651)
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.tag, "AndroidRuntime")
        XCTAssertEqual(entry.message, "FATAL EXCEPTION: main")
        XCTAssertEqual(entry.kind, .crash)
        XCTAssertEqual(entry.text, Real.lines[2])
    }

    func testPaddedTagsAreTrimmed() {
        let entry = LogEntry.parse("11-27 16:22:43.923  3024  5843 D Debug   : low && ship && 3rdparty app crash, do not dump", id: 0)
        XCTAssertEqual(entry.tag, "Debug")
        XCTAssertEqual(entry.message, "low && ship && 3rdparty app crash, do not dump")
        XCTAssertEqual(entry.kind, .normal, "the word crash alone does not make a crash")
    }

    func testEachKindOfCrashLineIsRecognised() {
        let kinds = Real.lines.map { LogEntry.parse($0, id: 0).kind }
        XCTAssertEqual(kinds, [.normal, .normal, .crash, .normal, .exception, .stackFrame, .stackFrame, .stackFrame, .normal, .processDied])
    }

    func testCausedByMoreAndAppPrintedTraces() {
        XCTAssertEqual(LogEntry.parse(line(9, "AndroidRuntime", "Caused by: java.io.IOException: boom", level: "E"), id: 0).kind, .causedBy)
        XCTAssertEqual(LogEntry.parse(line(9, "AndroidRuntime", "\t... 12 more", level: "E"), id: 0).kind, .stackFrame)
        XCTAssertEqual(LogEntry.parse(line(9, "System.err", "\tat com.game.Foo.bar(Foo.kt:12)", level: "W"), id: 0).kind, .stackFrame, "e.printStackTrace()")
        XCTAssertEqual(LogEntry.parse(line(9, "Game", "Caused by: java.lang.IllegalStateException: x"), id: 0).kind, .causedBy)
        XCTAssertEqual(LogEntry.parse(line(9, "Game", "I looked at (this) carefully"), id: 0).kind, .normal)
        XCTAssertEqual(LogEntry.parse(line(9, "Game", "at com.game.Foo.bar(Foo.kt:12)"), id: 0).kind, .normal, "without the tab it is just text")
    }

    func testNativeCrashAnrAndDeath() {
        XCTAssertEqual(LogEntry.parse(line(123, "libc", "Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0 in tid 123 (Thread-2), pid 123 (game)", level: "F"), id: 0).kind, .nativeCrash)
        XCTAssertEqual(LogEntry.parse(line(900, "DEBUG", "    #00 pc 0000000000012345  /system/lib64/libc.so (abort+168)", level: "F"), id: 0).kind, .stackFrame)
        XCTAssertEqual(LogEntry.parse(line(3024, "ActivityManager", "ANR in com.game (com.game/.Main)", level: "E"), id: 0).kind, .anr)
        XCTAssertTrue(LogEntry.Kind.anr.startsCrash)
        XCTAssertFalse(LogEntry.Kind.processDied.startsCrash)
    }

    func testLinesThatAreNotLogLinesAreKeptAsText() {
        for text in ["--------- beginning of crash", "", "garbage with spaces in it 1 2 3 4 5 6"] {
            let entry = LogEntry.parse(text, id: 1)
            XCTAssertEqual(entry.level, .verbose)
            XCTAssertNil(entry.pid)
            XCTAssertEqual(entry.kind, .normal)
            XCTAssertEqual(entry.text, text)
        }
    }
}

final class CrashGroupingTests: XCTestCase {
    private func grouped(_ lines: [String]) -> [LogEntry] {
        var grouper = CrashGrouper()
        return lines.enumerated().map { grouper.apply(to: LogEntry.parse($1, id: $0)) }
    }

    func testARealCrashIsOneBlockDespiteTheBannerAndOtherProcesses() {
        let entries = grouped(Real.lines)
        XCTAssertEqual(entries.map(\.crashBlock), [nil, nil, 1, 1, 1, 1, 1, 1, nil, nil],
                       "the header, the Process line, the exception and every frame; not the banner, other processes or the death notice")
    }

    func testTheReportEndsWhenTheSameProcessLogsSomethingElse() {
        let entries = grouped(Real.lines + [line(2651, "Zygote", "unrelated"), line(2651, "AndroidRuntime", "\tat late.Frame(Late.java:1)", level: "E")])
        XCTAssertNil(entries[10].crashBlock)
        XCTAssertNil(entries[11].crashBlock, "a frame after the report is over is not part of it")
    }

    func testTwoCrashesGetTwoBlocks() {
        let second = [line(500, "AndroidRuntime", "FATAL EXCEPTION: Thread-3", level: "E"), line(500, "AndroidRuntime", "\tat a.B.c(B.java:1)", level: "E")]
        let entries = grouped(Real.lines + second)
        XCTAssertEqual(entries[10].crashBlock, 2)
        XCTAssertEqual(entries[11].crashBlock, 2)
    }

    func testNativeCrashesIncludeTheTraceFromTheDumpProcess() {
        let entries = grouped([
            line(123, "libc", "Fatal signal 11 (SIGSEGV), code 1, fault addr 0x0", level: "F"),
            line(900, "DEBUG", "*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***", level: "F"),
            line(900, "DEBUG", "backtrace:", level: "F"),
            line(900, "DEBUG", "    #00 pc 0000000000012345  /system/lib64/libc.so (abort+168)", level: "F"),
        ])
        XCTAssertEqual(entries.map(\.crashBlock), [1, 1, 1, 1])
    }

    func testPlainLinesBeforeAnyCrashAreUntouched() {
        XCTAssertEqual(grouped([line(1, "A", "x"), line(2, "B", "y")]).map(\.crashBlock), [nil, nil])
    }
}

final class ProcessScopeTests: XCTestCase {
    func testTheRealProcessListIsParsed() {
        let processes = ProcessList.parse(Real.processList)
        XCTAssertEqual(processes.count, 6, "the header is skipped")
        XCTAssertEqual(processes.first?.name, "init")
        XCTAssertEqual(ProcessList.parse("garbage\n\n  12\n abc def").count, 0)
    }

    func testAnAppsProcessesAreItsOwnAndItsNamedOnesButNotALookAlike() {
        let processes = ProcessList.parse(Real.processList)
        XCTAssertEqual(ProcessList.pids(of: "com.android.settings", in: processes), [2651, 2700])
        XCTAssertEqual(ProcessList.pids(of: "com.sec.android.app.launcher", in: processes), [4888])
        XCTAssertEqual(ProcessList.pids(of: "com.nothing", in: processes), [])
    }

    func testScopeRules() {
        func entry(_ text: String, block: Int? = nil) -> LogEntry { var e = LogEntry.parse(text, id: 0); e.crashBlock = block; return e }
        XCTAssertTrue(LogScope.accepts(entry(line(2651, "X", "hi")), package: "com.game", pids: [2651], acceptedBlocks: []))
        XCTAssertFalse(LogScope.accepts(entry(line(9999, "X", "hi")), package: "com.game", pids: [2651], acceptedBlocks: []))
        XCTAssertTrue(LogScope.accepts(entry(line(3024, "ActivityManager", "Process com.game (pid 1) has died")), package: "com.game", pids: [], acceptedBlocks: []))
        XCTAssertTrue(LogScope.accepts(entry(line(900, "DEBUG", "backtrace:"), block: 4), package: "com.game", pids: [], acceptedBlocks: [4]))
        XCTAssertFalse(LogScope.accepts(entry(line(900, "DEBUG", "backtrace:"), block: 5), package: "com.game", pids: [], acceptedBlocks: [4]))
    }

    func testTheCrashReportNamesTheProcess() {
        XCTAssertEqual(LogScope.crashPID(in: "Process: com.game, PID: 4321", package: "com.game"), 4321)
        XCTAssertNil(LogScope.crashPID(in: "Process: com.other, PID: 4321", package: "com.game"))
        XCTAssertNil(LogScope.crashPID(in: "Process: com.game2, PID: 4321", package: "com.game"), "a package that merely starts the same way")
        XCTAssertNil(LogScope.crashPID(in: "no", package: "com.game"))
    }
}

@MainActor
final class LogcatModelScopeTests: XCTestCase {
    private func model(package: String? = "com.android.settings", knownProcesses: String? = Real.processList) -> LogcatModel {
        let model = LogcatModel()
        model.setForegroundPackage(package)
        if let knownProcesses { model.updateProcesses(from: knownProcesses) }
        return model
    }

    func testOnlyTheAppInFrontIsKept() {
        let model = model()
        let noise = [line(9999, "Other", "from another app"), line(4888, "Launcher", "from the launcher")]
        model.ingest(noise + [line(2651, "Settings", "from the app")] + Real.lines.suffix(1))
        XCTAssertEqual(model.entries.map(\.message), ["from the app", "Process com.android.settings (pid 2651) has died: fg  TOP (324,1726)"],
                       "its own lines, plus the system's note about it")
    }

    func testACrashOfTheAppIsKeptAsABlockAndCounted() {
        let model = model()
        model.ingest(Real.lines)
        XCTAssertEqual(model.crashIDs.count, 1)
        let block = model.entries.filter { $0.crashBlock == 1 }
        XCTAssertEqual(block.count, 6, "header, Process line, exception and 3 frames")
        XCTAssertEqual(model.entries.first { $0.id == model.crashIDs[0] }?.kind, .crash)
    }

    func testACrashOfAnotherAppIsLeftOut() {
        let model = model()
        model.ingest([line(7000, "AndroidRuntime", "FATAL EXCEPTION: main", level: "E"),
                      line(7000, "AndroidRuntime", "Process: com.other.app, PID: 7000", level: "E"),
                      line(7000, "AndroidRuntime", "\tat other.App.run(App.java:1)", level: "E"),
                      line(2651, "Settings", "ours")])
        XCTAssertEqual(model.entries.map(\.message), ["ours"])
        XCTAssertEqual(model.crashIDs, [])
    }

    func testACrashAtLaunchFromAnUnknownProcessIsStillCaught() {
        let model = model(knownProcesses: nil)
        model.ingest([line(8123, "AndroidRuntime", "Shutting down VM", level: "D"),
                      line(8123, "AndroidRuntime", "FATAL EXCEPTION: main", level: "E"),
                      line(8123, "AndroidRuntime", "Process: com.android.settings, PID: 8123", level: "E"),
                      line(8123, "AndroidRuntime", "java.lang.NullPointerException: oops", level: "E"),
                      line(8123, "AndroidRuntime", "\tat com.android.settings.Main.onCreate(Main.java:5)", level: "E"),
                      line(8123, "Settings", "a later line of the dead process")])
        XCTAssertEqual(model.crashIDs.count, 1)
        let kinds = model.entries.map(\.kind)
        XCTAssertTrue(kinds.contains(.crash), "the header that was waiting is released")
        XCTAssertTrue(kinds.contains(.exception))
        XCTAssertTrue(kinds.contains(.stackFrame))
        XCTAssertEqual(model.entries.first { $0.kind == .crash }?.crashBlock, model.entries.last { $0.kind == .stackFrame }?.crashBlock)
        XCTAssertTrue(model.entries.last?.message.contains("a later line") == true, "the pid is now known")
    }

    func testInterleavedLinesDoNotBreakAHeldCrash() {
        let model = model(knownProcesses: nil)
        model.ingest([line(8123, "AndroidRuntime", "FATAL EXCEPTION: main", level: "E"),
                      line(1, "Noise", "another process in between"),
                      line(8123, "AndroidRuntime", "Process: com.android.settings, PID: 8123", level: "E")])
        XCTAssertEqual(model.entries.map(\.kind), [.crash, .normal])
        XCTAssertEqual(model.crashIDs.count, 1)
    }

    func testEverythingModeKeepsAllLines() {
        let model = model()
        model.scope = .everything
        model.ingest([line(9999, "Other", "a"), line(2651, "Settings", "b")])
        XCTAssertEqual(model.entries.count, 2)
    }

    func testWithoutAKnownAppNothingIsFiltered() {
        let model = model(package: nil, knownProcesses: nil)
        model.ingest([line(9999, "Other", "a")])
        XCTAssertEqual(model.entries.count, 1)
    }

    func testAnotherAppStartsFreshButKeepsWhatWasCollected() {
        let model = model()
        model.ingest([line(2651, "Settings", "first app")])
        model.setForegroundPackage("com.sec.android.app.launcher")
        model.updateProcesses(from: Real.processList)
        model.ingest([line(2651, "Settings", "no longer followed"), line(4888, "Launcher", "second app")])
        XCTAssertEqual(model.entries.map(\.message), ["first app", "second app"])
    }

    func testTheCrashCountFollowsTheTrimming() {
        let model = model()
        model.ingest([line(2651, "AndroidRuntime", "FATAL EXCEPTION: main", level: "E")])
        XCTAssertEqual(model.crashIDs.count, 1)
        model.ingest((0..<LogcatModel.capacity).map { line(2651, "Settings", "filler \($0)") })
        XCTAssertEqual(model.entries.count, LogcatModel.capacity)
        XCTAssertEqual(model.crashIDs, [], "the crash scrolled out of the buffer")
    }

    func testClearForgetsEverything() {
        let model = model()
        model.ingest(Real.lines)
        model.clear()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertTrue(model.crashIDs.isEmpty)
    }
}

@MainActor
final class LogcatSnapshotTests: XCTestCase {
    func testACrashRendersAsAHighlightedBlock() throws {
        var grouper = CrashGrouper()
        let entries = (Real.lines + [line(2651, "Settings", "an ordinary line", level: "D")]).enumerated().map { grouper.apply(to: LogEntry.parse($1, id: $0)) }
        let view = LogList(entries: entries, followsTail: false, package: "com.android.settings", jumpTarget: .constant(nil))
        for (appearance, name) in [(NSAppearance.Name.aqua, "logcat-light"), (.darkAqua, "logcat-dark")] {
            let image = try renderSnapshot(view, size: CGSize(width: 900, height: 260), name: name, appearance: appearance)
            XCTAssertFalse(isBlankImage(image))
        }
    }
}

@MainActor
final class ChosenAppScopeTests: XCTestCase {
    func testAChosenAppKeepsItsLinesWhateverIsInFront() {
        let model = LogcatModel()
        model.setForegroundPackage("com.sec.android.app.launcher")
        model.scope = .chosenApp
        model.chosenPackage = "com.android.settings"
        model.updateProcesses(from: Real.processList)
        XCTAssertEqual(model.targetPackage, "com.android.settings")

        model.ingest(["11-27 16:22:40.000  2651  2651 I SettingsTag: from settings", "11-27 16:22:40.001  4888  4888 I LauncherTag: from the launcher"])
        XCTAssertEqual(model.entries.map(\.tag), ["SettingsTag"])
    }

    func testEverythingHasNoTargetAndChangingAppForgetsTheOldProcesses() {
        let model = LogcatModel()
        model.scope = .everything
        XCTAssertNil(model.targetPackage)
        model.scope = .chosenApp
        model.chosenPackage = "com.android.settings"
        model.updateProcesses(from: Real.processList)
        XCTAssertGreaterThan(model.knownProcessCount, 0)
        model.chosenPackage = "com.sec.android.app.launcher"
        XCTAssertEqual(model.knownProcessCount, 0)
    }
}
