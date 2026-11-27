import DomainModels
import Foundation
import Networking

/// What the Connect screen tells the user about the selected phone, and whether mirroring can start.
/// Pure, so every state of the screen is tested without a phone.
public struct ConnectStatus: Equatable {
    public enum Banner: Equatable {
        case adbMissing
        case noDevice
        case unauthorized
        case offline
        case failed(String)
    }

    /// The message card above the settings, if any. A failed start is shown with a ready phone, so the user can try again.
    public var banner: Banner?
    public var canStart: Bool
    public var isStarting: Bool

    public init(banner: Banner?, canStart: Bool, isStarting: Bool) {
        self.banner = banner
        self.canStart = canStart
        self.isStarting = isStarting
    }

    public static func make(adbMissing: Bool, devices: [AndroidDevice], selected: AndroidDevice?, state: AppModel.State) -> ConnectStatus {
        if adbMissing { return ConnectStatus(banner: .adbMissing, canStart: false, isStarting: false) }
        if state == .connecting { return ConnectStatus(banner: nil, canStart: false, isStarting: true) }
        guard let selected else {
            return ConnectStatus(banner: devices.isEmpty ? .noDevice : nil, canStart: false, isStarting: false)
        }
        switch selected.state {
        case .unauthorized: return ConnectStatus(banner: .unauthorized, canStart: false, isStarting: false)
        case .offline, .other: return ConnectStatus(banner: .offline, canStart: false, isStarting: false)
        case .device:
            if case let .failed(message) = state { return ConnectStatus(banner: .failed(message), canStart: true, isStarting: false) }
            return ConnectStatus(banner: nil, canStart: true, isStarting: false)
        }
    }
}

/// The short texts under a phone's name and on a quality card.
public enum ConnectText {
    /// "USB · Ready", "Wi-Fi · Unauthorized".
    public static func deviceStatus(_ device: AndroidDevice) -> String {
        "\(transport(of: device)) · \(stateName(device.state))"
    }

    /// "USB · 3A1F9C27": how it is connected and which phone it is, for the header.
    public static func deviceDetail(_ device: AndroidDevice) -> String {
        "\(transport(of: device)) · \(device.serial)"
    }

    /// A wireless serial looks like `192.168.1.24:41233`; a USB one never contains a colon.
    public static func transport(of device: AndroidDevice) -> String {
        device.serial.contains(":") ? String(localized: "Wi-Fi") : String(localized: "USB")
    }

    public static func stateName(_ state: AndroidDevice.State) -> String {
        switch state {
        case .device: return String(localized: "Ready")
        case .unauthorized: return String(localized: "Unauthorized")
        case .offline: return String(localized: "Offline")
        case .other: return String(localized: "Unavailable")
        }
    }

    /// "Native · 120 fps · steady 40 Mbps" — the numbers on a quality card, from the real values.
    public static func qualitySummary(_ quality: VideoQuality) -> String {
        let resolution = quality.maxSize == 0 ? String(localized: "Native") : "\(quality.maxSize) px"
        let rate = quality.constantBitRate ? String(localized: "steady \(quality.bitRateMbps) Mbps") : "\(quality.bitRateMbps) Mbps"
        return "\(resolution) · \(quality.maxFPS) fps · \(rate)"
    }

    /// "H.264 · 1920 px · 60 fps" — the line next to the Advanced heading.
    public static func advancedSummary(_ quality: VideoQuality) -> String {
        let resolution = quality.maxSize == 0 ? String(localized: "Native") : "\(quality.maxSize) px"
        return "\(quality.codec.shortName) · \(resolution) · \(quality.maxFPS) fps"
    }

    /// The usual choices of a picker, plus the saved value when it is not one of them (or the picker would show nothing).
    public static func options(_ usual: [Int], including current: Int) -> [Int] {
        usual.contains(current) ? usual : (usual + [current]).sorted()
    }
}
