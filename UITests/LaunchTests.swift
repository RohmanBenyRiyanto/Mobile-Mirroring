import XCTest

/// End-to-end smoke test: the app starts and shows its window. (Needs a Mac that allows UI automation.)
final class LaunchTests: XCTestCase {
    func testTheAppStartsAndShowsItsWindow() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.terminate()
    }
}
