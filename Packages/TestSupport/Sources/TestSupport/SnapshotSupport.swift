import AppKit
import SwiftUI
import XCTest

/// Renders a SwiftUI view to an image. Set `BENZMIRROR_SNAPSHOT_DIR` to also write it there as a PNG for a look.
@MainActor
public func renderSnapshot<Content: View>(_ view: Content, size: CGSize, name: String, appearance: NSAppearance.Name = .aqua) throws -> NSBitmapImageRep {
    let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    hosting.frame = CGRect(origin: .zero, size: size)
    hosting.appearance = NSAppearance(named: appearance)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()

    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)

    if let directory = ProcessInfo.processInfo.environment["BENZMIRROR_SNAPSHOT_DIR"],
       let png = bitmap.representation(using: .png, properties: [:]) {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
    return bitmap
}

/// True if the image is a single flat colour.
public func isBlankImage(_ image: NSBitmapImageRep) -> Bool {
    guard let first = image.colorAt(x: 0, y: 0) else { return true }
    for y in stride(from: 0, to: image.pixelsHigh, by: 17) {
        for x in stride(from: 0, to: image.pixelsWide, by: 17) where image.colorAt(x: x, y: y) != first { return false }
    }
    return true
}
