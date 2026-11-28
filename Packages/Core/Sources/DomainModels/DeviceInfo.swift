import CoreGraphics
import Foundation

public struct DeviceInfo: Equatable {
    public var manufacturer: String
    public var model: String
    public var androidRelease: String
    public var sdk: Int
    public var physicalSize: CGSize
    public var physicalDensity: Int
    public var overrideSize: CGSize?
    public var overrideDensity: Int?

    public init(manufacturer: String, model: String, androidRelease: String, sdk: Int, physicalSize: CGSize, physicalDensity: Int, overrideSize: CGSize? = nil, overrideDensity: Int? = nil) {
        self.manufacturer = manufacturer
        self.model = model
        self.androidRelease = androidRelease
        self.sdk = sdk
        self.physicalSize = physicalSize
        self.physicalDensity = physicalDensity
        self.overrideSize = overrideSize
        self.overrideDensity = overrideDensity
    }

    public var screenSize: CGSize { overrideSize ?? physicalSize }
    public var density: Int { overrideDensity ?? physicalDensity }

    public var densityScale: Double { Double(density) / 160 }

    public func dp(fromPixels pixels: Double) -> Double { pixels / densityScale }
    public func pixels(fromDP dp: Double) -> Double { dp * densityScale }

    public func screenSize(matching frame: CGSize) -> CGSize {
        let landscape = frame.width > frame.height
        let isLandscape = screenSize.width > screenSize.height
        return landscape == isLandscape ? screenSize : CGSize(width: screenSize.height, height: screenSize.width)
    }
}

public enum DeviceInfoParser {
    public static let command = "wm size; wm density; echo release=$(getprop ro.build.version.release); echo sdk=$(getprop ro.build.version.sdk); echo maker=$(getprop ro.product.manufacturer); echo model=$(getprop ro.product.model)"

    public static func parse(_ output: String) -> DeviceInfo? {
        var physicalSize: CGSize?, overrideSize: CGSize?
        var physicalDensity: Int?, overrideDensity: Int?
        var values: [String: String] = [:]

        for line in output.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let text = value(of: line, after: "Physical size:") { physicalSize = size(from: text) }
            else if let text = value(of: line, after: "Override size:") { overrideSize = size(from: text) }
            else if let text = value(of: line, after: "Physical density:") { physicalDensity = density(from: text) }
            else if let text = value(of: line, after: "Override density:") { overrideDensity = density(from: text) }
            else if let separator = line.firstIndex(of: "=") {
                values[String(line[..<separator])] = String(line[line.index(after: separator)...])
            }
        }

        guard let physicalSize, let physicalDensity else { return nil }
        return DeviceInfo(manufacturer: clean(values["maker"]), model: clean(values["model"]),
                          androidRelease: clean(values["release"]), sdk: Int(values["sdk"] ?? "") ?? 0,
                          physicalSize: physicalSize, physicalDensity: physicalDensity,
                          overrideSize: overrideSize, overrideDensity: overrideDensity)
    }

    // MARK: Helpers

    private static func value(of line: String, after prefix: String) -> String? {
        line.hasPrefix(prefix) ? line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) : nil
    }

    private static func size(from text: String) -> CGSize? {
        let parts = text.split(separator: "x")
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]),
              (1...16_384).contains(width), (1...16_384).contains(height)
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func density(from text: String) -> Int? {
        guard let value = Int(text), (60...1_200).contains(value) else { return nil }
        return value
    }

    private static func clean(_ text: String?) -> String {
        String((text ?? "").unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }.map(Character.init).prefix(64))
    }
}
