import Foundation

public func projectFile(_ relativePath: String, from file: StaticString = #filePath) -> URL {
    var folder = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: folder.appendingPathComponent(relativePath).path), folder.path != "/" {
        folder.deleteLastPathComponent()
    }
    return folder.appendingPathComponent(relativePath)
}
