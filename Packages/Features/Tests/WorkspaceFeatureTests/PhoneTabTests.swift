import Networking
import XCTest
@testable import WorkspaceFeature

final class PhoneTabTests: XCTestCase {
    func testMirroredPhonesFirstThenOfflineOnes() {
        let tabs = PhoneTab.tabs(
            mirrored: [("A", "Pixel", true), ("B", "", false)],
            devices: [AndroidDevice(serial: "A", state: .device, model: nil), AndroidDevice(serial: "C", state: .offline, model: "Galaxy_S"),
                      AndroidDevice(serial: "D", state: .device, model: "Other")],
            activeSerial: "B")
        XCTAssertEqual(tabs.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(tabs[1].title, "B")
        XCTAssertTrue(tabs[1].isActive)
        XCTAssertTrue(tabs[0].isRecording)
        XCTAssertTrue(tabs[2].isOffline)
        XCTAssertEqual(tabs[2].title, "Galaxy S")
    }
}
