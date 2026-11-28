import Foundation
import UniformTypeIdentifiers

public enum PhoneClipboardPlan {
    public static let folder = "/sdcard/Download/Benz Mirror Paste"
    public static let helperPath = "/data/local/tmp/benz-clip.dex"
    public static let maxFileBytes = 200 << 20
    public static let maxFiles = 10

    public static func mimeType(forFileNamed name: String) -> String {
        let ext = (name as NSString).pathExtension
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    public static func phoneName(_ original: String, index: Int) -> String {
        let cleaned = original.map { $0.isLetter || $0.isNumber || ".-_ ()".contains($0) ? $0 : "_" }
        let base = String(cleaned.prefix(100)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "\(index + 1)-\(base.isEmpty ? "file" : base)"
    }

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

    public static func helperCommand(items: [(uri: String, mime: String)]) -> String {
        let arguments = items.flatMap { [PhoneTransfer.shellQuoted($0.uri), PhoneTransfer.shellQuoted(isSafeMime($0.mime) ? $0.mime : "application/octet-stream")] }
        return "CLASSPATH=\(helperPath) app_process /system/bin dev.benz.mirror.ClipHelper " + arguments.joined(separator: " ")
    }

    public static let readCommand = "CLASSPATH=\(helperPath) app_process /system/bin dev.benz.mirror.ClipHelper get"
    public static let removeFolderCommand = "rm -rf " + PhoneTransfer.shellQuoted(folder)

    static func isSafeMime(_ mime: String) -> Bool {
        mime.count <= 100 && mime.contains("/") && mime.allSatisfy { $0.isLetter || $0.isNumber || "/+-.".contains($0) }
    }

    public static func clipboardURIs(fromHelperOutput output: String) -> [(uri: String, mime: String?)] {
        guard output.hasPrefix("clip") else { return [] }
        let parts = output.split(whereSeparator: \.isWhitespace).dropFirst().map(String.init)
        let mime = parts.first { !$0.hasPrefix("uri=") }
        return parts.filter { $0.hasPrefix("uri=content://") }.map { (String($0.dropFirst(4)), mime) }
    }
}
