import Networking
import XCTest
@testable import WorkspaceFeature

final class OnboardingFlowTests: XCTestCase {
    func testStepsMoveWithinBounds() {
        var flow = OnboardingFlow()
        XCTAssertTrue(flow.isFirst)
        flow.back()
        XCTAssertEqual(flow.step, .developerOptions)
        flow.next(); flow.next()
        XCTAssertTrue(flow.isLast)
        flow.next()
        XCTAssertEqual(flow.step, .allowMac)
        flow.back()
        XCTAssertEqual(flow.step, .usbDebugging)
    }

    func testPhoneState() {
        XCTAssertEqual(OnboardingFlow.phone(in: []), .waiting)
        let unauthorized = AndroidDevice(serial: "A", state: .unauthorized, model: nil)
        XCTAssertEqual(OnboardingFlow.phone(in: [unauthorized]), .unauthorized)
        let ready = AndroidDevice(serial: "B", state: .device, model: "Pixel_8")
        XCTAssertEqual(OnboardingFlow.phone(in: [unauthorized, ready]), .ready(name: "Pixel 8", serial: "B"))
    }

    @MainActor
    func testFinishingIsRemembered() {
        let defaults = isolatedDefaults()
        XCTAssertTrue(AppModel(defaults: defaults).showsOnboarding)
        let model = AppModel(defaults: defaults)
        model.finishOnboarding()
        XCTAssertFalse(model.showsOnboarding)
        XCTAssertFalse(AppModel(defaults: defaults).showsOnboarding)
    }
}

@MainActor
final class PerDeviceSettingsTests: XCTestCase {
    func testEachPhoneKeepsItsOwnChoices() {
        let defaults = isolatedDefaults()
        let model = AppModel(defaults: defaults)
        model.selectedSerial = "A"
        model.settings.showTouches = true
        model.selectedSerial = "B"
        XCTAssertTrue(model.settings.showTouches, "a phone seen for the first time starts from the current settings")
        model.settings.showTouches = false
        model.selectedSerial = "A"
        XCTAssertTrue(model.settings.showTouches)
        model.selectedSerial = "B"
        XCTAssertFalse(model.settings.showTouches)

        let again = AppModel(defaults: defaults)
        again.selectedSerial = "A"
        XCTAssertTrue(again.settings.showTouches, "remembered across launches")
    }
}

@MainActor
final class DisplayShapeMemoryTests: XCTestCase {
    func testShapeIsRememberedAcrossLaunchesAndBadNamesAreIgnored() {
        let defaults = isolatedDefaults()
        let model = AppModel(defaults: defaults)
        model.rememberDisplayShape("com.example.game", landscape: true)
        model.rememberDisplayShape("bad name; x", landscape: true)
        let dictionary = defaults.dictionary(forKey: "displayShapes.v1") as? [String: Bool]
        XCTAssertEqual(dictionary, ["com.example.game": true])
    }
}
