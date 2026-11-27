import Foundation
import XCTest

/// Runs an executable from Homebrew and returns its status and stderr, or skips the test if it is missing.
public func runTool(_ name: String, _ arguments: [String]) throws -> (status: Int32, output: String, errors: String) {
    guard let path = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
        throw XCTSkip("\(name) is not installed")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let output = out.fileHandleForReading.readDataToEndOfFile()
    let errors = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self), String(decoding: errors, as: UTF8.self))
}

