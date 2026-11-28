import XCTest

/// Requires a Mac that allows UI automation. Run: xcodebuild … test -only-testing:UITests
final class LaunchTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        // First launch shows the welcome sheet; skip it so the tests see the Connect window.
        let skip = app.buttons["Skip Setup"]
        if skip.waitForExistence(timeout: 2) { skip.click() }
        return app
    }

    func testTheAppStartsAndShowsItsWindow() throws {
        let app = launch()
        app.terminate()
    }

    func testSettingsOpensWithTheCommaShortcut() throws {
        let app = launch()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows.matching(NSPredicate(format: "title CONTAINS[c] 'General' OR title CONTAINS[c] 'Settings' OR title CONTAINS[c] 'Pengaturan'")).firstMatch.waitForExistence(timeout: 5)
                      || app.windows.count >= 2)
        app.terminate()
    }

    func testTheMenuBarHasTheDesignedMenus() throws {
        let app = launch()
        for title in ["File", "Edit", "View", "Mirror", "Device", "Keymap", "Logcat", "Window", "Help"] {
            XCTAssertTrue(app.menuBars.menuBarItems[title].exists, "missing menu \(title)")
        }
        app.terminate()
    }
}
