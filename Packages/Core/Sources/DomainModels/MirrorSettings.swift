import Foundation

public enum VideoCodec: String, CaseIterable, Identifiable, Codable {
    case h264, h265

    public var id: String { rawValue }

    public var wireID: UInt32 {
        switch self {
        case .h264: return 0x6832_3634
        case .h265: return 0x6832_3635
        }
    }

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

public struct VideoQuality: Equatable, Codable {
    public static let maxSizeRange = 0...4096
    public static let bitRateRange = 1...200
    public static let frameRateRange = 15...120
    public static let keyFrameIntervalRange = 1...10

    public var codec: VideoCodec = .h264
    public var maxSize = 1920
    public var bitRateMbps = 8
    public var maxFPS = 60
    public var keyFrameIntervalSeconds = 10
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

public enum AudioSource: String, Codable, CaseIterable, Sendable {
    case output
    case mic
}

public struct VirtualDisplaySettings: Equatable, Codable, Sendable {
    public var isEnabled = false
    public var startApp: String?
    public var initialLandscape = false

    public init(isEnabled: Bool = false, startApp: String? = nil, initialLandscape: Bool = false) {
        self.initialLandscape = initialLandscape
        self.isEnabled = isEnabled
        self.startApp = startApp
    }
}

public struct MirrorSettings: Equatable, Codable {
    public static let streamPortRange = 1024...65535

    public var quality = VideoQuality()
    public var audioEnabled = true
    public var audioSource = AudioSource.output
    public var audioVolume = 1.0
    public var audioOutputUID: String?
    public var recordAudio = true
    public var confirmDisconnect = true
    public var quitWhenWindowCloses = false
    public var adbPath: String?
    public var confirmRecording = true
    public var confirmInstall = true
    public var confirmNetworkOff = true
    public var confirmDiscardKeymap = true
    public var audioBufferMillis = 120
    public static let audioBufferRange = 40...300
    public var virtualDisplay = VirtualDisplaySettings()
    public var showTouches = false
    public var stayAwake = false
    public var turnScreenOffOnStart = false
    public var autoKeymap = true
    public var autoEnableKeymap = true
    public var obsStreamEnabled = false
    public var obsStreamPort = 8765
    public var mirrorOnConnect = false
    public var autoGamingMode = false
    public var screenshotFolder: String?
    public var recordingFolder: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MirrorSettings()
        quality = try values.decodeIfPresent(VideoQuality.self, forKey: .quality) ?? defaults.quality
        audioEnabled = try values.decodeIfPresent(Bool.self, forKey: .audioEnabled) ?? defaults.audioEnabled
        virtualDisplay = (try? values.decodeIfPresent(VirtualDisplaySettings.self, forKey: .virtualDisplay)).flatMap { $0 } ?? defaults.virtualDisplay
        audioOutputUID = try values.decodeIfPresent(String.self, forKey: .audioOutputUID)
        confirmDisconnect = try values.decodeIfPresent(Bool.self, forKey: .confirmDisconnect) ?? defaults.confirmDisconnect
        adbPath = try values.decodeIfPresent(String.self, forKey: .adbPath)
        quitWhenWindowCloses = try values.decodeIfPresent(Bool.self, forKey: .quitWhenWindowCloses) ?? defaults.quitWhenWindowCloses
        confirmRecording = try values.decodeIfPresent(Bool.self, forKey: .confirmRecording) ?? defaults.confirmRecording
        confirmInstall = try values.decodeIfPresent(Bool.self, forKey: .confirmInstall) ?? defaults.confirmInstall
        confirmNetworkOff = try values.decodeIfPresent(Bool.self, forKey: .confirmNetworkOff) ?? defaults.confirmNetworkOff
        confirmDiscardKeymap = try values.decodeIfPresent(Bool.self, forKey: .confirmDiscardKeymap) ?? defaults.confirmDiscardKeymap
        recordAudio = try values.decodeIfPresent(Bool.self, forKey: .recordAudio) ?? defaults.recordAudio
        audioVolume = min(max(try values.decodeIfPresent(Double.self, forKey: .audioVolume) ?? defaults.audioVolume, 0), 1)
        audioBufferMillis = Self.clamp(try values.decodeIfPresent(Int.self, forKey: .audioBufferMillis) ?? defaults.audioBufferMillis, Self.audioBufferRange)
        audioSource = (try? values.decodeIfPresent(AudioSource.self, forKey: .audioSource)).flatMap { $0 } ?? defaults.audioSource
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

    public func serverArguments(scid: UInt32) -> [String] {
        let quality = self.quality
        var codecOptions = ["i-frame-interval:int=\(Self.clamp(quality.keyFrameIntervalSeconds, VideoQuality.keyFrameIntervalRange))"]
        if quality.constantBitRate { codecOptions.append("bitrate-mode:int=2") }

        var arguments = [
            "scid=" + String(format: "%08x", scid),
            "log_level=warn",
            "audio=\(audioEnabled)",
            "audio_source=\(audioSource.rawValue)",
            "audio_codec=raw",
            "control=true",
            "clipboard_autosync=false",
            "video_codec=\(quality.codec.rawValue)",
            "max_size=\(Self.clamp(quality.maxSize, VideoQuality.maxSizeRange))",
            "video_bit_rate=\(Self.clamp(quality.bitRateMbps, VideoQuality.bitRateRange) * 1_000_000)",
            "max_fps=\(Self.clamp(quality.maxFPS, VideoQuality.frameRateRange))",
            "video_codec_options=" + codecOptions.joined(separator: ","),
            "show_touches=\(showTouches)",
            "stay_awake=\(stayAwake)",
        ]
        if virtualDisplay.isEnabled { arguments += virtualDisplayArguments() }
        return arguments
    }

    public var virtualDisplayApp: String? {
        guard virtualDisplay.isEnabled, let app = virtualDisplay.startApp, ForegroundApp.isValidPackage(app) else { return nil }
        return app
    }

    private func virtualDisplayArguments() -> [String] {
        let size = VirtualDisplayMath.initialSize(landscape: virtualDisplay.initialLandscape)
        var arguments = [
            "new_display=\(size.width)x\(size.height)/\(VirtualDisplayMath.density(shortEdge: min(size.width, size.height)))",
            "flex_display=true",
            "vd_system_decorations=false",
            "vd_destroy_content=false",
        ]
        return arguments
    }

    public static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
