import DomainModels
import Foundation

@MainActor
public final class PhoneLedgerStore {
    private let defaults: UserDefaults
    private static let key = "phoneLedger.v1"
    private(set) var ledger: PhoneChangeLedger

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        ledger = defaults.data(forKey: Self.key).flatMap(PhoneChangeLedger.decode) ?? PhoneChangeLedger()
    }

    public func entry(for serial: String) -> PhoneChangeLedger.Entry? { ledger.entry(for: serial) }

    public func recordBaseline(_ baseline: DeveloperState, for serial: String) { change { $0.recordBaseline(baseline, for: serial) } }
    public func clearBaseline(for serial: String) { change { $0.clearBaseline(for: serial) } }
    public func setMockLocation(_ active: Bool, for serial: String) { change { $0.setMockLocation(active, for: serial) } }
    public func clear(_ serial: String) { change { $0.clear(serial) } }

    private func change(_ edit: (inout PhoneChangeLedger) -> Void) {
        edit(&ledger)
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: Self.key) }
    }
}
