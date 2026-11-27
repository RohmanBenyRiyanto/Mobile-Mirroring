import AppKit
import Networking
import Foundation
import DomainModels

/// Where screenshots and recordings are saved: `<Pictures|Movies>/<app name>/<Prefix>-<timestamp>.<ext>`.
public enum OutputFiles {
    /// A new file name in the user's chosen folder (`custom`, when it exists), else in `<Pictures or Movies>/Benz Mirror`.
    public static func newURL(in directory: FileManager.SearchPathDirectory, prefix: String, pathExtension: String, custom: String? = nil) throws -> URL {
        let folder: URL
        var isDirectory: ObjCBool = false
        if let custom, custom.hasPrefix("/"), FileManager.default.fileExists(atPath: custom, isDirectory: &isDirectory), isDirectory.boolValue {
            folder = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: directory, in: .userDomainMask)[0].appendingPathComponent(AppInfo.name, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return folder.appendingPathComponent("\(prefix)-\(formatter.string(from: Date())).\(pathExtension)")
    }

    /// Limits the name to safe characters before it is used on the phone.
    public static func sanitizedName(_ name: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-() ")
        let cleaned = String(name.map { allowed.contains($0) ? $0 : "_" }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "file" + cleaned : String(cleaned.prefix(120))
    }
}

extension AppModel {
    public func takeScreenshot() {
        guard let adb, let serial = targetSerial else { return }
        Task {
            do {
                let png = try await Task.detached { try adb.run(["-s", serial, "exec-out", "screencap", "-p"], timeout: 15) }.value
                let url = try OutputFiles.newURL(in: .picturesDirectory, prefix: "Screenshot", pathExtension: "png", custom: settings.screenshotFolder)
                try png.write(to: url, options: .withoutOverwriting)
                notice = String(localized: "Saved \(url.lastPathComponent) to Pictures/\(AppInfo.name)")
                noticeFile = url
            } catch {
                notice = String(localized: "Screenshot failed: \(error.localizedDescription)")
            }
        }
    }

    /// Dropped files: an `.apk` is installed, a `.benzkeymap` is imported, anything else is copied to the phone's Download folder.
    public func handleDrop(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            switch url.pathExtension.lowercased() {
            case "apk": install(apk: url)
            case KeymapFile.fileExtension: importKeymap(from: url) // a shared keymap, not a file for the phone
            default: push(file: url)
            }
        }
    }

    private func install(apk: URL) {
        guard let adb, let serial = targetSerial else { return }
        notice = String(localized: "Installing \(apk.lastPathComponent)…")
        Task {
            do {
                let downgraded = try await Task.detached { try Self.installAllowingDowngrade(adb: adb, serial: serial, apk: apk) }.value
                notice = downgraded ? String(localized: "Installed \(apk.lastPathComponent) (older version replaced the newer one)") : String(localized: "Installed \(apk.lastPathComponent)")
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    /// Updates in place first; only when adb says the file is an older version does it retry with the downgrade flag. Returns true if it did.
    nonisolated private static func installAllowingDowngrade(adb: ADB, serial: String, apk: URL) throws -> Bool {
        do {
            _ = try adb.run(["-s", serial, "install", "-r", apk.path], timeout: 180)
            return false
        } catch {
            guard PhoneTransfer.isDowngradeRefusal(error.localizedDescription) else { throw error }
            _ = try adb.run(["-s", serial, "install", "-r", "-d", apk.path], timeout: 180)
            return true
        }
    }

    private func push(file: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            notice = String(localized: "Folders cannot be copied to the phone")
            return
        }
        guard let adb, let serial = targetSerial else { return }
        let name = OutputFiles.sanitizedName(file.lastPathComponent)
        let kind = PhoneTransfer.kind(ofFileNamed: name)
        let folder = PhoneTransfer.folder(for: kind, appName: AppInfo.name)
        notice = String(localized: "Copying \(name)…")
        Task {
            do {
                try await Task.detached {
                    _ = try adb.run(["-s", serial, "shell", "mkdir -p " + PhoneTransfer.shellQuoted(folder)], timeout: 10)
                    _ = try adb.run(["-s", serial, "push", file.path, "\(folder)/\(name)"], timeout: 600)
                    if kind != .other { _ = try? adb.run(["-s", serial, "shell", PhoneTransfer.scanCommand(forPhonePath: "\(folder)/\(name)")], timeout: 10) }
                }.value
                notice = kind == .other ? String(localized: "Copied \(name) to Download") : String(localized: "Copied \(name) to Gallery")
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    public func run(_ tool: DeviceTool) {
        guard let adb, let serial = targetSerial else { return }
        Task {
            do {
                for command in tool.shellCommands {
                    _ = try await Task.detached { try adb.run(["-s", serial, "shell"] + command, timeout: 10) }.value
                }
                notice = String(localized: String.LocalizationValue(tool.title))
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    // MARK: Wireless

    public func switchToWireless() {
        guard let adb, let serial = selectedSerial else { return }
        notice = String(localized: "Switching to Wi-Fi…")
        Task {
            do {
                let address = try await Task.detached { try adb.enableWireless(serial: serial) }.value
                notice = String(localized: "Connected wirelessly at \(address). You can unplug the cable.")
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    public func switchToUSB() {
        guard let adb, let serial = selectedSerial else { return }
        Task {
            do {
                try await Task.detached { try adb.switchToUSB(serial: serial) }.value
                notice = String(localized: "Back in USB mode. Plug the cable in.")
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    public func pair(address: String, code: String) {
        guard let adb else { return }
        Task {
            do {
                try await Task.detached { try adb.pair(address: address, code: code) }.value
                notice = String(localized: "Paired. Now connect using the address shown on the main wireless screen.")
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    public func connectWireless(address: String) {
        guard let adb else { return }
        Task {
            do {
                try await Task.detached { try adb.connect(address: address) }.value
                notice = String(localized: "Connected to \(address)")
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    // MARK: Helpers

    private func perform(_ start: String, done: String, timeout: TimeInterval, arguments: @escaping @Sendable (String) -> [String]) {
        guard let adb, let serial = targetSerial else { return }
        notice = start
        Task {
            do {
                _ = try await Task.detached { try adb.run(arguments(serial), timeout: timeout) }.value
                notice = done
            } catch {
                notice = error.localizedDescription
            }
        }
    }
}
