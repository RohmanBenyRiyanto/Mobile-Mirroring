import DomainModels
import Foundation
import Networking

/// Pure logic, so every screen state can be tested without a phone.
public struct ConnectStatus: Equatable {
    public enum Banner: Equatable {
        case adbMissing
        case noDevice
        case unauthorized
        case offline
        case failed(String)
    }

    /// A failed start is shown even when the phone is ready, so the user can try again.
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

public enum ConnectText {
    public static func deviceStatus(_ device: AndroidDevice) -> String {
        "\(transport(of: device)) · \(stateName(device.state))"
    }

    public static func deviceDetail(_ device: AndroidDevice) -> String {
        "\(transport(of: device)) · \(device.serial)"
    }

    /// Wireless serials contain a colon (host:port); USB serials never do.
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

    public static func qualitySummary(_ quality: VideoQuality) -> String {
        let resolution = quality.maxSize == 0 ? String(localized: "Native") : "\(quality.maxSize) px"
        let rate = quality.constantBitRate ? String(localized: "steady \(quality.bitRateMbps) Mbps") : "\(quality.bitRateMbps) Mbps"
        return "\(resolution) · \(quality.maxFPS) fps · \(rate)"
    }

    public static func advancedSummary(_ quality: VideoQuality) -> String {
        let resolution = quality.maxSize == 0 ? String(localized: "Native") : "\(quality.maxSize) px"
        return "\(quality.codec.shortName) · \(resolution) · \(quality.maxFPS) fps"
    }

    /// The usual choices, plus the current value when it is not one of them so the picker never shows nothing.
    public static func options(_ usual: [Int], including current: Int) -> [Int] {
        usual.contains(current) ? usual : (usual + [current]).sorted()
    }
}
