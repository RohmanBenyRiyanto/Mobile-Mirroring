import AppKit
import SwiftUI
import TestSupport
import Theme
import XCTest
@testable import WorkspaceFeature

final class RecordingPillTests: XCTestCase {
    func testClockFormatsMinutesAndHours() {
        XCTAssertEqual(RecordingPill.clock(0), "00:00")
        XCTAssertEqual(RecordingPill.clock(83), "01:23")
        XCTAssertEqual(RecordingPill.clock(3599), "59:59")
        XCTAssertEqual(RecordingPill.clock(3725), "1:02:05")
        XCTAssertEqual(RecordingPill.clock(-5), "00:00", "a clock that ran backwards must not show a negative time")
    }
}

@MainActor
final class RailTests: XCTestCase {
    private func model() -> AppModel {
        AppModel(keymapRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: isolatedDefaults())
    }

    func testRailRendersExpandedAndCollapsedInBothAppearances() throws {
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let expanded = RailView(model: model(), isCollapsed: .constant(false))
            XCTAssertFalse(isBlankImage(try renderSnapshot(expanded, size: CGSize(width: 100, height: 740), name: "rail-expanded-\(suffix)", appearance: appearance)))
            let collapsed = RailView(model: model(), isCollapsed: .constant(true))
            XCTAssertFalse(isBlankImage(try renderSnapshot(collapsed, size: CGSize(width: 100, height: 120), name: "rail-collapsed-\(suffix)", appearance: appearance)))
        }
    }

    func testPanelSitsBesideTheWindowAndNeverTakesFocus() throws {
        let window = NSWindow(contentRect: CGRect(x: 200, y: 150, width: 300, height: 560), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false // a window made in code would otherwise be released twice
        defer { window.close() }
        let controller = RailPanelController(parent: window, content: AnyView(Color.clear.frame(width: 92, height: 500)))
        let panel = try XCTUnwrap(window.childWindows?.first)

        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isOpaque)
        // 12 pt beside the window, less the 20 pt of transparent room the rail keeps for its shadow.
        XCTAssertEqual(panel.frame.minX, window.frame.maxX + 12 - 20, accuracy: 1)
        XCTAssertEqual(panel.frame.midY, window.frame.midY, accuracy: 1, "centered on the window's height")

        window.setFrame(CGRect(x: 300, y: 150, width: 340, height: 520), display: false)
        XCTAssertEqual(panel.frame.minX, window.frame.maxX + 12 - 20, accuracy: 1, "follows a resize")

        controller.setVisible(false)
        XCTAssertNil(window.childWindows?.first, "hidden: no longer attached")
        controller.setVisible(true)
        XCTAssertEqual(window.childWindows?.count, 1, "shown again")
        controller.detach()
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }
}

@MainActor
final class WindowShapeTests: XCTestCase {
    func testWindowTakesThePhonesShapeWhenMirroringStarts() throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 512), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let styler = WindowStyler(isStreamMode: false, alwaysOnTop: false, videoSize: CGSize(width: 1080, height: 2340), locksAspect: true)
        window.contentView = NSHostingView(rootView: Color.clear.background(styler))
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        let size = window.contentLayoutRect.size
        XCTAssertEqual(size.width / size.height, 1080.0 / 2340.0, accuracy: 0.01)
        XCTAssertEqual(window.contentAspectRatio.width / window.contentAspectRatio.height, 1080.0 / 2340.0, accuracy: 0.001)
    }

    func testWindowIsFreeWhenNotMirroring() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 512), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: Color.clear.background(WindowStyler(isStreamMode: false, alwaysOnTop: false, videoSize: CGSize(width: 1080, height: 2340))))
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(window.contentLayoutRect.size.width, 760, accuracy: 1, "the Connect window keeps its own size")
    }
}

final class DropSummaryTests: XCTestCase {
    private func file(_ name: String, bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(count: bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testApkIsInstalled() throws {
        let summary = try XCTUnwrap(DropSummary.make(from: [try file("app-debug.apk", bytes: 24_600_000)]))
        XCTAssertEqual(summary.action, .install)
        XCTAssertTrue(summary.detail.contains("app-debug.apk"))
        XCTAssertTrue(summary.detail.contains("MB"), summary.detail)
    }

    func testKeymapIsImportedAndOtherFilesCopied() throws {
        XCTAssertEqual(DropSummary.make(from: [try file("pubg.benzkeymap", bytes: 10)])?.action, .import_)
        XCTAssertEqual(DropSummary.make(from: [try file("photo.png", bytes: 10)])?.action, .copy)
    }

    func testSeveralFilesAreCountedAndNothingIsNil() throws {
        let many = DropSummary.make(from: [try file("a.png", bytes: 1), try file("b.png", bytes: 1), try file("c.png", bytes: 1)])
        XCTAssertEqual(many?.detail, "3 files")
        XCTAssertNil(DropSummary.make(from: []))
        XCTAssertNil(DropSummary.make(from: [URL(string: "https://example.com/a.apk")!]), "only files on this Mac count")
    }
}

@MainActor
final class MirrorOverlayRenderTests: XCTestCase {
    func testToastAndDropOverlayAndPillRender() throws {
        SurfaceStyle.allowsGlass = false
        defer { SurfaceStyle.allowsGlass = true }
        let size = CGSize(width: 368, height: 560)
        let toast = ZStack(alignment: .bottom) {
            Color(red: 0.1, green: 0.3, blue: 0.7)
            ToastView(text: "Saved Screenshot-20261127-1042.png to Pictures/Benz Mirror", file: URL(fileURLWithPath: "/tmp/x.png")) {}
        }
        XCTAssertFalse(isBlankImage(try renderSnapshot(toast, size: size, name: "mirror-toast")))
        let drop = DropOverlay(summary: DropSummary(action: .install, detail: "app-debug.apk · 24.6 MB"))
        XCTAssertFalse(isBlankImage(try renderSnapshot(ZStack { Color.blue; drop }, size: size, name: "mirror-drop")))
        let pill = ZStack(alignment: .top) { Color(red: 0.1, green: 0.3, blue: 0.7); RecordingPill(startedAt: Date().addingTimeInterval(-134)) }
        XCTAssertFalse(isBlankImage(try renderSnapshot(pill, size: size, name: "mirror-pill")))
    }
}

final class WindowSizeMemoryTests: XCTestCase {
    private let connect = CGSize(width: 760, height: 512)
    private let ratio: CGFloat = 1080.0 / 2340.0

    func testTheFirstLookStartsAtTheConnectSizeWhateverFrameWasRestored() {
        var memory = WindowSizeMemory()
        XCTAssertEqual(memory.update(isPhoneShaped: false, currentContentSize: CGSize(width: 380, height: 820), availableHeight: 1000, pictureRatio: nil), connect,
                       "a phone-shaped frame restored from last time must not open the Connect window")
        var already = WindowSizeMemory()
        XCTAssertNil(already.update(isPhoneShaped: false, currentContentSize: connect, availableHeight: 1000, pictureRatio: nil))
    }

    func testMirroringTakesThePhonesShapeAtTheDesignHeight() throws {
        var memory = WindowSizeMemory()
        _ = memory.update(isPhoneShaped: false, currentContentSize: connect, availableHeight: 1000, pictureRatio: nil)
        let size = try XCTUnwrap(memory.update(isPhoneShaped: true, currentContentSize: connect, availableHeight: 1000, pictureRatio: ratio))
        XCTAssertEqual(size.height, 818)
        XCTAssertEqual(size.width / size.height, ratio, accuracy: 0.002)
    }

    func testASmallScreenKeepsTheWindowOnScreen() throws {
        var memory = WindowSizeMemory()
        _ = memory.update(isPhoneShaped: false, currentContentSize: connect, availableHeight: 700, pictureRatio: nil)
        let size = try XCTUnwrap(memory.update(isPhoneShaped: true, currentContentSize: connect, availableHeight: 700, pictureRatio: ratio))
        XCTAssertLessThanOrEqual(size.height, 620)
    }

    func testDisconnectingGoesBackToTheConnectSizeTheUserHad() throws {
        var memory = WindowSizeMemory()
        _ = memory.update(isPhoneShaped: false, currentContentSize: connect, availableHeight: 1000, pictureRatio: nil)
        let userSize = CGSize(width: 900, height: 600) // the user made the Connect window bigger
        _ = memory.update(isPhoneShaped: false, currentContentSize: userSize, availableHeight: 1000, pictureRatio: nil)
        _ = memory.update(isPhoneShaped: true, currentContentSize: userSize, availableHeight: 1000, pictureRatio: ratio)
        let back = try XCTUnwrap(memory.update(isPhoneShaped: false, currentContentSize: CGSize(width: 340, height: 740), availableHeight: 1000, pictureRatio: nil))
        XCTAssertEqual(back, userSize, "not left phone-shaped")
    }

    func testThePhoneWindowComesBackAtTheHeightItLastHad() throws {
        var memory = WindowSizeMemory()
        _ = memory.update(isPhoneShaped: false, currentContentSize: connect, availableHeight: 1000, pictureRatio: nil)
        _ = memory.update(isPhoneShaped: true, currentContentSize: connect, availableHeight: 1000, pictureRatio: ratio)
        _ = memory.update(isPhoneShaped: false, currentContentSize: CGSize(width: 330, height: 700), availableHeight: 1000, pictureRatio: nil)
        let again = try XCTUnwrap(memory.update(isPhoneShaped: true, currentContentSize: connect, availableHeight: 1000, pictureRatio: ratio))
        XCTAssertEqual(again.height, 700)
    }

    func testRotationKeepsTheHeightAndChangesTheShape() throws {
        var memory = WindowSizeMemory()
        _ = memory.update(isPhoneShaped: false, currentContentSize: connect, availableHeight: 1000, pictureRatio: nil)
        _ = memory.update(isPhoneShaped: true, currentContentSize: connect, availableHeight: 1000, pictureRatio: ratio)
        let landscape: CGFloat = 2340.0 / 1080.0
        let size = try XCTUnwrap(memory.update(isPhoneShaped: true, currentContentSize: CGSize(width: 377, height: 818), availableHeight: 1000, pictureRatio: landscape))
        XCTAssertEqual(size.width / size.height, landscape, accuracy: 0.01)
        XCTAssertNil(memory.update(isPhoneShaped: true, currentContentSize: size, availableHeight: 1000, pictureRatio: landscape), "already the right shape: leave it")
    }
}

final class RailShortcutHintTests: XCTestCase {
    func testHintsAreUniqueAndFollowTheMenus() {
        let hints = RailItemID.allCases.compactMap(\.shortcutHint)
        XCTAssertEqual(hints.count, Set(hints).count)
        XCTAssertEqual(RailItemID.back.shortcutHint, "⌘[")
        XCTAssertEqual(RailItemID.streamMode.shortcutHint, "⇧⌘B")
    }
}

final class WindowFitTests: XCTestCase {
    private func phoneWindow() -> WindowSizeMemory {
        var memory = WindowSizeMemory()
        _ = memory.update(isPhoneShaped: false, currentContentSize: WindowSizeMemory.defaultConnectSize, availableHeight: 1000, pictureRatio: nil)
        _ = memory.update(isPhoneShaped: true, currentContentSize: WindowSizeMemory.defaultConnectSize, availableHeight: 1000, pictureRatio: 0.5)
        return memory
    }

    func testOpeningASidePanelDoesNotSendTheWindowBackToTheConnectSize() {
        var memory = phoneWindow()
        XCTAssertNil(memory.update(isPhoneShaped: true, currentContentSize: CGSize(width: 700, height: 818), availableHeight: 1000, pictureRatio: 0.5, fit: .free))
    }

    func testAFlexibleDisplayOnlyFollowsARotation() {
        var memory = phoneWindow()
        XCTAssertNil(memory.update(isPhoneShaped: true, currentContentSize: CGSize(width: 500, height: 800), availableHeight: 1000, pictureRatio: 0.7, fit: .orientation))
        let rotated = memory.update(isPhoneShaped: true, currentContentSize: CGSize(width: 500, height: 800), availableHeight: 1000, pictureRatio: 16.0 / 9, fit: .orientation)
        XCTAssertNotNil(rotated)
        XCTAssertGreaterThan(rotated?.width ?? 0, rotated?.height ?? 1)
    }
}

final class WindowPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 940)

    func testATallWindowSlidesUpInsteadOfLeavingTheScreen() {
        // A 870 pt window whose top is 200 pt below the top of the screen would hang off the bottom.
        let old = CGRect(x: 376, y: 940 - 200 - 564, width: 760, height: 564)
        let frame = WindowPlacement.resized(old, to: CGSize(width: 387, height: 870), in: screen)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.minX, 376)
    }

    func testASmallResizeKeepsTheTopLeftCorner() {
        let old = CGRect(x: 100, y: 300, width: 400, height: 500)
        let frame = WindowPlacement.resized(old, to: CGSize(width: 300, height: 400), in: screen)
        XCTAssertEqual(frame.minX, 100)
        XCTAssertEqual(frame.maxY, 800)
    }

    func testAWiderWindowSlidesLeftWhenTheRightEdgeRunsOut() {
        let frame = WindowPlacement.fitted(CGRect(x: 1300, y: 100, width: 600, height: 500), in: screen)
        XCTAssertEqual(frame.maxX, screen.maxX)
        XCTAssertEqual(frame.width, 600)
    }

    func testAWindowLargerThanTheScreenIsShrunk() {
        let frame = WindowPlacement.fitted(CGRect(x: 0, y: 0, width: 4000, height: 3000), in: screen)
        XCTAssertEqual(frame.size, screen.size)
    }
}
