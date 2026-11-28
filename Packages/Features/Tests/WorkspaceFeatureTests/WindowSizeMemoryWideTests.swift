import XCTest
@testable import WorkspaceFeature

final class WindowSizeMemoryWideTests: XCTestCase {
    func testARotatedPhoneNeverMakesTheWindowWiderThanTheScreen() {
        var memory = WindowSizeMemory()
        _ = memory.update(isPhoneShaped: false, currentContentSize: CGSize(width: 760, height: 512), availableHeight: 900, availableWidth: 1512, pictureRatio: nil)
        let portrait = memory.update(isPhoneShaped: true, currentContentSize: CGSize(width: 760, height: 512), availableHeight: 900, availableWidth: 1512, pictureRatio: 0.46)
        XCTAssertNotNil(portrait)
        let landscape = memory.update(isPhoneShaped: true, currentContentSize: CGSize(width: 376, height: 818), availableHeight: 900, availableWidth: 1512, pictureRatio: 2.17)
        let size = try! XCTUnwrap(landscape)
        XCTAssertLessThanOrEqual(size.width, 1512)
        XCTAssertEqual(size.width / size.height, 2.17, accuracy: 0.02, "the window keeps the picture's shape, so there are no bands")
    }
}
