import DomainModels
import Foundation
import DomainModels

// What the phone is asked through adb. The questions themselves (fixed text) and the parsers live in DomainModels.

extension DeviceInfo {
    /// Asks a phone for its details through adb.
    public static func fetch(adb: ADB, serial: String) throws -> DeviceInfo {
        let output = String(decoding: try adb.run(["-s", serial, "shell", DeviceInfoParser.command], timeout: 10), as: UTF8.self)
        guard let info = DeviceInfoParser.parse(output) else {
            throw ADBError.failed(command: "device info", message: "The phone did not report its screen size.")
        }
        return info
    }
}

extension ForegroundAppDetector {
    /// Runs the dumpsys query on a phone through adb.
    public static func fetcher(adb: ADB, serial: String) -> @Sendable () throws -> String {
        { String(decoding: try adb.run(["-s", serial, "shell", ForegroundAppParser.command], timeout: 5), as: UTF8.self) }
    }
}
