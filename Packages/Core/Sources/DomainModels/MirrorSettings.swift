import Foundation

public enum VideoCodec: String, CaseIterable, Identifiable, Codable {
    case h264, h265

    public var id: String { rawValue }

    /// Four-character codec id the server sends at the start of the video stream.
    public var wireID: UInt32 {
        switch self {
        case .h264: return 0x6832_3634 // "h264"
        case .h265: return 0x6832_3635 // "h265"
        }
    }

    /// "H.264" / "H.265", for tight spaces.
    public var shortName: String { self == .h264 ? "H.264" : "H.265" }

    public var title: String { self == .h264 ? "H.264 (most compatible)" : "H.265 (better quality per bit)" }
}

public enum QualityPreset: String, CaseIterable, Identifiable {
    case balanced, high, gaming, maximum, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .high: return "High quality"
        case .gaming: return "Game streaming"
        case .maximum: return "Maximum"
        case .custom: return "Custom"
        }
    }

    public var summary: String {
        switch self {
        case .balanced: return "1920 px, 8 Mbps, 60 fps. Light on USB and Wi-Fi."
        case .high: return "Native resolution, 20 Mbps, 60 fps."
        case .gaming: return "Native resolution, 40 Mbps constant, 60 fps, 1 s keyframes. Good for OBS."
        case .maximum: return "Native resolution, 80 Mbps constant, 120 fps, H.265. USB recommended."
        case .custom: return "Your own values."
        }
    }
}

/// Everything that shapes the picture the phone encodes.
public struct VideoQuality: Equatable, Codable {
    public static let maxSizeRange = 0...4096
    public static let bitRateRange = 1...200
    public static let frameRateRange = 15...120
    public static let keyFrameIntervalRange = 1...10

    public var codec: VideoCodec = .h264
    /// Longest video edge in pixels; 0 keeps the device resolution.
    public var maxSize = 1920
    public var bitRateMbps = 8
    public var maxFPS = 60
    /// Seconds between key frames. A short interval lets a late viewer (OBS) start quickly.
    public var keyFrameIntervalSeconds = 10
    /// Constant bit rate keeps a steady stream, which suits streaming; variable favors still scenes.
    public var constantBitRate = false

    public init(codec: VideoCodec = .h264, maxSize: Int = 1920, bitRateMbps: Int = 8, maxFPS: Int = 60, keyFrameIntervalSeconds: Int = 10, constantBitRate: Bool = false) {
        self.codec = codec
        self.maxSize = maxSize
        self.bitRateMbps = bitRateMbps
        self.maxFPS = maxFPS
        self.keyFrameIntervalSeconds = keyFrameIntervalSeconds
        self.constantBitRate = constantBitRate
    }

    public static func values(for preset: QualityPreset) -> VideoQuality? {
        switch preset {
        case .balanced:
            return VideoQuality()
        case .high:
            return VideoQuality(codec: .h264, maxSize: 0, bitRateMbps: 20, maxFPS: 60, keyFrameIntervalSeconds: 2, constantBitRate: false)
        case .gaming:
            return VideoQuality(codec: .h264, maxSize: 0, bitRateMbps: 40, maxFPS: 60, keyFrameIntervalSeconds: 1, constantBitRate: true)
        case .maximum:
            return VideoQuality(codec: .h265, maxSize: 0, bitRateMbps: 80, maxFPS: 120, keyFrameIntervalSeconds: 1, constantBitRate: true)
        case .custom:
            return nil
        }
    }

    public var matchingPreset: QualityPreset {
        QualityPreset.allCases.first { Self.values(for: $0) == self } ?? .custom
    }
}

public struct MirrorSettings: Equatable, Codable {
    public static let streamPortRange = 1024...65535

    public var quality = VideoQuality()
    /// Android 11+; older devices simply stream without sound.
    public var audioEnabled = true
    public var showTouches = false
    public var stayAwake = false
    public var turnScreenOffOnStart = false
    public var autoKeymap = true
    /// Also switches that keymap on, and off again when the game closes.
    public var autoEnableKeymap = true
    /// Re-serves the phone's stream on loopback as MPEG-TS, for OBS.
    public var obsStreamEnabled = false
    public var obsStreamPort = 8765
    public var mirrorOnConnect = false
    /// Switches to Gaming mode when a game with a keymap opens. Off by default, since modes change only when the user changes them.
    public var autoGamingMode = false
    /// Where screenshots and recordings are saved; nil keeps Pictures/Benz Mirror and Movies/Benz Mirror.
    public var screenshotFolder: String?
    public var recordingFolder: String?

    public init() {}

    /// Settings saved by an older version lack the newer fields; they get their defaults instead of failing to load.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MirrorSettings()
        quality = try values.decodeIfPresent(VideoQuality.self, forKey: .quality) ?? defaults.quality
        audioEnabled = try values.decodeIfPresent(Bool.self, forKey: .audioEnabled) ?? defaults.audioEnabled
        showTouches = try values.decodeIfPresent(Bool.self, forKey: .showTouches) ?? defaults.showTouches
        stayAwake = try values.decodeIfPresent(Bool.self, forKey: .stayAwake) ?? defaults.stayAwake
        turnScreenOffOnStart = try values.decodeIfPresent(Bool.self, forKey: .turnScreenOffOnStart) ?? defaults.turnScreenOffOnStart
        autoKeymap = try values.decodeIfPresent(Bool.self, forKey: .autoKeymap) ?? defaults.autoKeymap
        autoEnableKeymap = try values.decodeIfPresent(Bool.self, forKey: .autoEnableKeymap) ?? defaults.autoEnableKeymap
        obsStreamEnabled = try values.decodeIfPresent(Bool.self, forKey: .obsStreamEnabled) ?? defaults.obsStreamEnabled
        obsStreamPort = try values.decodeIfPresent(Int.self, forKey: .obsStreamPort) ?? defaults.obsStreamPort
        mirrorOnConnect = try values.decodeIfPresent(Bool.self, forKey: .mirrorOnConnect) ?? defaults.mirrorOnConnect
        autoGamingMode = try values.decodeIfPresent(Bool.self, forKey: .autoGamingMode) ?? defaults.autoGamingMode
        screenshotFolder = try values.decodeIfPresent(String.self, forKey: .screenshotFolder)
        recordingFolder = try values.decodeIfPresent(String.self, forKey: .recordingFolder)
    }

    /// `key=value` arguments for the server. Every value is clamped or enumerated,
    /// so nothing user-supplied can reach the device shell as free text.
    public func serverArguments(scid: UInt32) -> [String] {
        let quality = self.quality
        var codecOptions = ["i-frame-interval:int=\(Self.clamp(quality.keyFrameIntervalSeconds, VideoQuality.keyFrameIntervalRange))"]
        if quality.constantBitRate { codecOptions.append("bitrate-mode:int=2") } // MediaCodecInfo BITRATE_MODE_CBR

        return [
            "scid=" + String(format: "%08x", scid),
            "log_level=warn",
            "audio=\(audioEnabled)",
            "audio_codec=raw", // 48 kHz 16-bit stereo PCM: no decoder, so no extra latency
            "control=true",
            "clipboard_autosync=false", // the clipboard only crosses over on an explicit action
            "video_codec=\(quality.codec.rawValue)",
            "max_size=\(Self.clamp(quality.maxSize, VideoQuality.maxSizeRange))",
            "video_bit_rate=\(Self.clamp(quality.bitRateMbps, VideoQuality.bitRateRange) * 1_000_000)",
            "max_fps=\(Self.clamp(quality.maxFPS, VideoQuality.frameRateRange))",
            "video_codec_options=" + codecOptions.joined(separator: ","),
            "show_touches=\(showTouches)",
            "stay_awake=\(stayAwake)",
        ]
    }

    public static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
