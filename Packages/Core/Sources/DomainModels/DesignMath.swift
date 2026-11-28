import CoreGraphics
import ImageIO
import Foundation

public enum DesignGrid: Int, CaseIterable, Identifiable {
    case off = 0, dp4 = 4, dp8 = 8
    public var id: Int { rawValue }
    public var title: String { self == .off ? "Grid Off" : "\(rawValue) dp Grid" }
    public var stepDP: Double? { self == .off ? nil : Double(rawValue) }
    public var majorEvery: Int { 4 }

    public static func lines(extentPixels: Double, densityScale: Double, stepDP: Double, viewLength: Double,
                      majorEvery: Int = 4, minimumSpacing: Double = 3) -> [(ratio: Double, isMajor: Bool)] {
        guard extentPixels > 0, densityScale > 0, stepDP > 0, viewLength > 0 else { return [] }
        let stepPixels = stepDP * densityScale
        guard stepPixels / extentPixels * viewLength >= minimumSpacing else { return [] }
        var result: [(Double, Bool)] = []
        var index = 1
        while Double(index) * stepPixels < extentPixels, index < 4096 {
            result.append((Double(index) * stepPixels / extentPixels, index % max(majorEvery, 1) == 0))
            index += 1
        }
        return result
    }
}

public struct PixelImage {
    public let width: Int
    public let height: Int
    private let rgba: [UInt8]

    public static let maxPixels = 64 * 1024 * 1024

    public init?(png data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0, image.width * image.height <= Self.maxPixels else { return nil }
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        width = image.width
        height = image.height
        rgba = buffer
    }

    public func color(atRatio ratio: CGPoint) -> PickedColor? {
        guard ratio.x >= 0, ratio.x <= 1, ratio.y >= 0, ratio.y <= 1 else { return nil }
        let x = min(Int(ratio.x * Double(width)), width - 1)
        let y = min(Int(ratio.y * Double(height)), height - 1)
        let offset = (y * width + x) * 4
        return PickedColor(red: rgba[offset], green: rgba[offset + 1], blue: rgba[offset + 2], x: x, y: y)
    }
}

public struct PickedColor: Equatable {
    public let red: UInt8, green: UInt8, blue: UInt8
    public let x: Int, y: Int

    public init(red: UInt8, green: UInt8, blue: UInt8, x: Int, y: Int) {
        self.red = red
        self.green = green
        self.blue = blue
        self.x = x
        self.y = y
    }

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    public var rgbText: String { "rgb(\(red), \(green), \(blue))" }
}

public struct CrosshairReadout: Equatable {
    public let pixelX: Int, pixelY: Int
    public let dpX: Double?, dpY: Double?
    public let rightPixels: Int, bottomPixels: Int

    public init?(ratio: CGPoint, screenSize: CGSize, densityScale: Double?) {
        guard screenSize.width >= 1, screenSize.height >= 1, (0...1).contains(ratio.x), (0...1).contains(ratio.y) else { return nil }
        pixelX = min(Int(ratio.x * screenSize.width), Int(screenSize.width) - 1)
        pixelY = min(Int(ratio.y * screenSize.height), Int(screenSize.height) - 1)
        rightPixels = Int(screenSize.width) - 1 - pixelX
        bottomPixels = Int(screenSize.height) - 1 - pixelY
        if let scale = densityScale, scale > 0 {
            dpX = Double(pixelX) / scale
            dpY = Double(pixelY) / scale
        } else {
            dpX = nil
            dpY = nil
        }
    }

    private static func dp(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    public var pixelText: String { "\(pixelX), \(pixelY) px" }
    public var dpText: String? { dpX.flatMap { x in dpY.map { "\(Self.dp(x)), \(Self.dp($0)) dp" } } }
    public var edgesText: String { "→ \(rightPixels) px   ↓ \(bottomPixels) px" }
}
