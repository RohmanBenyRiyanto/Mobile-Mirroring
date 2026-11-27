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
