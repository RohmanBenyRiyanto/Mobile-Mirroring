import XCTest
@testable import DomainModels

final class PhoneChangeLedgerTests: XCTestCase {
    func testFirstBaselineWinsAndCleanEntriesVanish() {
        var ledger = PhoneChangeLedger()
        var original = DeveloperState()
        original.nightMode = .yes
        ledger.recordBaseline(original, for: "A")
        var changed = original
        changed.wifiOn = false
        ledger.recordBaseline(changed, for: "A")
        XCTAssertEqual(ledger.entry(for: "A")?.baseline, original, "a later change must not replace what the phone really had")

        ledger.clearBaseline(for: "A")
        XCTAssertNil(ledger.entry(for: "A"), "nothing owed, nothing kept")
    }

    func testRestorePlanUndoesTheDifferenceAndMockLocation() {
        var ledger = PhoneChangeLedger()
        let baseline = DeveloperState()
        ledger.recordBaseline(baseline, for: "A")
        ledger.setMockLocation(true, for: "A")
        var now = baseline
        now.wifiOn = false
        now.dontKeepActivities = true
        let commands = PhoneChangeLedger.restoreCommands(for: ledger.entry(for: "A")!, current: now)
        XCTAssertEqual(commands.first, MockLocation.stopCommand)
        XCTAssertTrue(commands.contains("svc wifi enable"))
        XCTAssertTrue(commands.contains("settings put global always_finish_activities 0"))
    }

    func testAPhoneThatRebootedNeedsNoCommands() {
        var ledger = PhoneChangeLedger()
        ledger.recordBaseline(DeveloperState(), for: "A")
        XCTAssertTrue(PhoneChangeLedger.restoreCommands(for: ledger.entry(for: "A")!, current: DeveloperState()).isEmpty)
    }

    func testRoundTripAndLimits() throws {
        var ledger = PhoneChangeLedger()
        for i in 0..<(PhoneChangeLedger.maxPhones + 5) { ledger.setMockLocation(true, for: "S\(i)") }
        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(PhoneChangeLedger.decode(data), ledger)
        XCTAssertNil(PhoneChangeLedger.decode(Data(count: PhoneChangeLedger.maxBytes + 1)))
        XCTAssertNil(PhoneChangeLedger.decode(Data("nope".utf8)))
    }
}
