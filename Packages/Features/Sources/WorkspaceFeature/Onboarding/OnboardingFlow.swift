import Networking

/// The three first-run steps and what the third one shows, decided from the phones adb reports. Pure, so it is tested without a window.
struct OnboardingFlow: Equatable {
    enum Step: Int, CaseIterable { case developerOptions, usbDebugging, allowMac }

    enum Phone: Equatable {
        case waiting
        case unauthorized
        case ready(name: String, serial: String)
    }

    var step = Step.developerOptions

    var isFirst: Bool { step == .developerOptions }
    var isLast: Bool { step == .allowMac }

    mutating func next() { if let following = Step(rawValue: step.rawValue + 1) { step = following } }
    mutating func back() { if let previous = Step(rawValue: step.rawValue - 1) { step = previous } }

    /// A ready phone wins; otherwise a phone that has not allowed this Mac; otherwise nothing yet.
    static func phone(in devices: [AndroidDevice]) -> Phone {
        if let ready = devices.first(where: \.isReady) { return .ready(name: ready.title, serial: ready.serial) }
        if devices.contains(where: { $0.state == .unauthorized }) { return .unauthorized }
        return .waiting
    }
}
