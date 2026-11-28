import Foundation
import UniformTypeIdentifiers

/// The pieces of "paste a file into the app on the phone": where the file waits, how its media-store address is found, and the helper command.
/// The helper puts a `content://` address on the phone's clipboard; the app that is pasted into reads the file through it.
public enum PhoneClipboardPlan {
    /// Visible to the media store (a hidden folder would not get an address) and removed again when the session ends.
    public static let folder = "/sdcard/Download/Benz Mirror Paste"
    public static let helperPath = "/data/local/tmp/benz-clip.dex"
    public static let maxFileBytes = 200 << 20
    public static let maxFiles = 10

    public static func mimeType(forFileNamed name: String) -> String {
        let ext = (name as NSString).pathExtension
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    /// A name safe to use on the phone, with a number in front so two files with the same name do not overwrite each other.
    public static func phoneName(_ original: String, index: Int) -> String {
        let cleaned = original.map { $0.isLetter || $0.isNumber || ".-_ ()".contains($0) ? $0 : "_" }
        let base = String(cleaned.prefix(100)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "\(index + 1)-\(base.isEmpty ? "file" : base)"
    }

    /// Finds the media-store row of a file that was just pushed and scanned.
    /// The media store records `/storage/emulated/0/…`, not the `/sdcard/…` spelling adb uses.
    public static func queryCommand(forPhonePath path: String) -> String {
        let path = path.hasPrefix("/sdcard/") ? "/storage/emulated/0/" + path.dropFirst("/sdcard/".count) : path
        return "content query --uri content://media/external/file --projection _id --where " + PhoneTransfer.shellQuoted("_data='\(path.replacingOccurrences(of: "'", with: "''"))'")
    }

    public static func mediaID(inQueryOutput output: String) -> Int? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: "_id=") else { continue }
            let digits = line[range.upperBound...].prefix { $0.isNumber }
            if let id = Int(digits) { return id }
        }
        return nil
    }

    public static func contentURI(forMediaID id: Int) -> String { "content://media/external/file/\(id)" }

    /// The shell command that runs the helper with `uri mime` pairs. Everything is built here from numbers and checked mime types.
    public static func helperCommand(items: [(uri: String, mime: String)]) -> String {
        let arguments = items.flatMap { [PhoneTransfer.shellQuoted($0.uri), PhoneTransfer.shellQuoted(isSafeMime($0.mime) ? $0.mime : "application/octet-stream")] }
        return "CLASSPATH=\(helperPath) app_process /system/bin dev.benz.mirror.ClipHelper " + arguments.joined(separator: " ")
    }

    public static let readCommand = "CLASSPATH=\(helperPath) app_process /system/bin dev.benz.mirror.ClipHelper get"
    public static let removeFolderCommand = "rm -rf " + PhoneTransfer.shellQuoted(folder)

    static func isSafeMime(_ mime: String) -> Bool {
        mime.count <= 100 && mime.contains("/") && mime.allSatisfy { $0.isLetter || $0.isNumber || "/+-.".contains($0) }
    }

    /// `clip image/png uri=content://media/external/file/12 …` → the addresses of what is on the phone's clipboard.
    public static func clipboardURIs(fromHelperOutput output: String) -> [(uri: String, mime: String?)] {
        guard output.hasPrefix("clip") else { return [] }
        let parts = output.split(whereSeparator: \.isWhitespace).dropFirst().map(String.init)
        let mime = parts.first { !$0.hasPrefix("uri=") }
        return parts.filter { $0.hasPrefix("uri=content://") }.map { (String($0.dropFirst(4)), mime) }
    }
}
