import XCTest
@testable import DomainModels

final class PhoneTransferTests: XCTestCase {
    func testKindsAndFolders() {
        XCTAssertEqual(PhoneTransfer.kind(ofFileNamed: "Photo.JPG"), .image)
        XCTAssertEqual(PhoneTransfer.kind(ofFileNamed: "clip.mp4"), .video)
        XCTAssertEqual(PhoneTransfer.kind(ofFileNamed: "notes.txt"), .other)
        XCTAssertEqual(PhoneTransfer.folder(for: .image, appName: "Benz Mirror"), "/sdcard/Pictures/Benz Mirror")
        XCTAssertEqual(PhoneTransfer.folder(for: .video, appName: "A/../B"), "/sdcard/Movies/AB")
        XCTAssertEqual(PhoneTransfer.folder(for: .other, appName: "x"), "/sdcard/Download")
    }

    func testScanCommandQuotesThePath() {
        XCTAssertEqual(PhoneTransfer.scanCommand(forPhonePath: "/sdcard/Pictures/a b.png"),
                       "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d 'file:///sdcard/Pictures/a b.png'")
        XCTAssertTrue(PhoneTransfer.shellQuoted("it's").contains("'\\''"))
    }

    func testDowngradeRefusal() {
        XCTAssertTrue(PhoneTransfer.isDowngradeRefusal("Failure [INSTALL_FAILED_VERSION_DOWNGRADE]"))
        XCTAssertFalse(PhoneTransfer.isDowngradeRefusal("Failure [INSTALL_FAILED_OLDER_SDK]"))
    }
}
