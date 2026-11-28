import XCTest
@testable import DomainModels

final class PhoneClipboardPlanTests: XCTestCase {
    func testNamesAreSafeAndNumbered() {
        XCTAssertEqual(PhoneClipboardPlan.phoneName("My photo (1).png", index: 0), "1-My photo (1).png")
        XCTAssertFalse(PhoneClipboardPlan.phoneName("../../evil;rm.sh", index: 0).contains("/"))
        XCTAssertFalse(PhoneClipboardPlan.phoneName("a;b`c$(d)", index: 0).contains(";"))
        XCTAssertEqual(PhoneClipboardPlan.phoneName("...", index: 0), "1-file")
    }

    func testMimeTypesAndTheHelperCommand() {
        XCTAssertEqual(PhoneClipboardPlan.mimeType(forFileNamed: "a.png"), "image/png")
        XCTAssertEqual(PhoneClipboardPlan.mimeType(forFileNamed: "a.pdf"), "application/pdf")
        XCTAssertEqual(PhoneClipboardPlan.mimeType(forFileNamed: "a.unknownext"), "application/octet-stream")
        let command = PhoneClipboardPlan.helperCommand(items: [("content://media/external/file/12", "image/png"), ("content://media/external/file/13", "bad mime; reboot")])
        XCTAssertTrue(command.hasPrefix("CLASSPATH=/data/local/tmp/benz-clip.dex app_process"))
        XCTAssertTrue(command.contains("'content://media/external/file/12' 'image/png'"))
        XCTAssertTrue(command.contains("'application/octet-stream'"), "an odd mime type is replaced, never passed to the shell")
        XCTAssertFalse(command.contains("reboot"))
    }

    func testFindingTheMediaAddress() {
        XCTAssertEqual(PhoneClipboardPlan.mediaID(inQueryOutput: "Row: 0 _id=1000036975\n"), 1000036975)
        XCTAssertNil(PhoneClipboardPlan.mediaID(inQueryOutput: "No result found.\n"))
        XCTAssertTrue(PhoneClipboardPlan.queryCommand(forPhonePath: "/a/it's.png").contains("it'\\'''\\''s"), "a quote is doubled for SQL, then escaped for the shell")
        XCTAssertEqual(PhoneClipboardPlan.contentURI(forMediaID: 5), "content://media/external/file/5")
    }

    func testReadingWhatTheClipboardHolds() {
        let items = PhoneClipboardPlan.clipboardURIs(fromHelperOutput: "clip image/png uri=content://media/external/file/7 uri=content://x/y\n")
        XCTAssertEqual(items.map(\.uri), ["content://media/external/file/7", "content://x/y"])
        XCTAssertEqual(items.first?.mime, "image/png")
        XCTAssertTrue(PhoneClipboardPlan.clipboardURIs(fromHelperOutput: "empty").isEmpty)
        XCTAssertTrue(PhoneClipboardPlan.clipboardURIs(fromHelperOutput: "clip text/plain").isEmpty)
    }
}
