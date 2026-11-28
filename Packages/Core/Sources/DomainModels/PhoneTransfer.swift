import Foundation

public enum PhoneTransfer {
    public enum Kind: Equatable { case image, video, other }

    public static func kind(ofFileNamed name: String) -> Kind {
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp": return .image
        case "mp4", "mov", "mkv", "webm", "3gp", "m4v": return .video
        default: return .other
        }
    }

    public static let destinationFolder = "/sdcard/Download"

    public static func scanCommand(forPhonePath path: String) -> String {
        "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d " + shellQuoted("file://" + path)
    }

    public static func shellQuoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    public static func isDowngradeRefusal(_ message: String) -> Bool { message.contains("INSTALL_FAILED_VERSION_DOWNGRADE") }
}
