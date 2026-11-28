import AppKit
import SwiftUI
import XCTest

@MainActor
public func renderSnapshot<Content: View>(_ view: Content, size: CGSize, name: String, appearance: NSAppearance.Name = .aqua) throws -> NSBitmapImageRep {
    let scale = ProcessInfo.processInfo.environment["BENZMIRROR_SNAPSHOT_SCALE"].flatMap(Double.init).map { CGFloat($0) } ?? 1
    let drawn = CGSize(width: size.width * scale, height: size.height * scale)
    let framed = view.frame(width: size.width, height: size.height)
    let hosting = scale == 1
        ? NSHostingView(rootView: AnyView(framed))
        : NSHostingView(rootView: AnyView(framed.scaleEffect(scale, anchor: .topLeading).frame(width: drawn.width, height: drawn.height, alignment: .topLeading)))
    hosting.frame = CGRect(origin: .zero, size: drawn)
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

public func isBlankImage(_ image: NSBitmapImageRep) -> Bool {
    guard let first = image.colorAt(x: 0, y: 0) else { return true }
    for y in stride(from: 0, to: image.pixelsHigh, by: 17) {
        for x in stride(from: 0, to: image.pixelsWide, by: 17) where image.colorAt(x: x, y: y) != first { return false }
    }
    return true
}
