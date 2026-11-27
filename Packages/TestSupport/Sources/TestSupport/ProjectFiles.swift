import Foundation

/// A file of the project (for example `docs/examples/example.benzkeymap`), found by walking up from the calling test file,
/// so it works wherever the test target sits in the folder tree.
public func projectFile(_ relativePath: String, from file: StaticString = #filePath) -> URL {
    var folder = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: folder.appendingPathComponent(relativePath).path), folder.path != "/" {
        folder.deleteLastPathComponent()
    }
    return folder.appendingPathComponent(relativePath)
}
