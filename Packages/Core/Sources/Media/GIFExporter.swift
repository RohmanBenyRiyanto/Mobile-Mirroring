import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum GIFExporter {
    public struct Options: Equatable, Sendable {
        public var start: Double
        public var length: Double
        public var framesPerSecond: Int
        public var maxWidth: Int

        public init(start: Double = 0, length: Double = 10, framesPerSecond: Int = 12, maxWidth: Int = 480) {
            self.start = start
            self.length = length
            self.framesPerSecond = framesPerSecond
            self.maxWidth = maxWidth
        }

        public var clamped: Options {
            Options(start: max(start, 0), length: min(max(length, 0.2), 30), framesPerSecond: min(max(framesPerSecond, 2), 24), maxWidth: min(max(maxWidth, 64), 960))
        }
    }

    public enum ExportError: LocalizedError {
        case noVideo, cannotWrite
        public var errorDescription: String? {
            switch self {
            case .noVideo: return "That file has no video to turn into a GIF."
            case .cannotWrite: return "The GIF could not be saved."
            }
        }
    }

    public static func frameTimes(duration: Double, options: Options) -> [Double] {
        let o = options.clamped
        let end = min(o.start + o.length, duration)
        guard end > o.start else { return [] }
        let step = 1.0 / Double(o.framesPerSecond)
        return stride(from: o.start, to: end, by: step).map { $0 }
    }

    public static func export(video: URL, to destination: URL, options: Options = Options()) async throws {
        let asset = AVURLAsset(url: video)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw ExportError.noVideo }
        let duration = try await asset.load(.duration).seconds
        let times = frameTimes(duration: duration, options: options)
        guard !times.isEmpty else { throw ExportError.noVideo }
        let o = options.clamped

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: o.maxWidth, height: o.maxWidth * 4)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        guard let target = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, times.count, nil) else { throw ExportError.cannotWrite }
        CGImageDestinationSetProperties(target, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(o.framesPerSecond)]] as CFDictionary

        for time in times {
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            CGImageDestinationAddImage(target, image, frameProperties)
        }
        guard CGImageDestinationFinalize(target) else { throw ExportError.cannotWrite }
    }
}
