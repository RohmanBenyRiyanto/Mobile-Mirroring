import Foundation

public struct DeviceNameDirectory: Sendable {
    private let models: [String: String]
    private let devices: [String: String]

    public init(models: [String: String] = [:], devices: [String: String] = [:]) {
        self.models = models
        self.devices = devices
    }

    public init?(json: Data) {
        struct File: Decodable { var models: [String: String]; var devices: [String: String] }
        guard let file = try? JSONDecoder().decode(File.self, from: json) else { return nil }
        self.init(models: file.models, devices: file.devices)
    }

    public static let bundled: DeviceNameDirectory = {
        guard let url = Bundle.main.url(forResource: "DeviceNames", withExtension: "json"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return DeviceNameDirectory() }
        return DeviceNameDirectory(json: data) ?? DeviceNameDirectory()
    }()

    public func name(model: String?, codename: String? = nil) -> String? {
        if let model, !model.isEmpty {
            let key = model.lowercased()
            if let found = models[key] ?? models[key.replacingOccurrences(of: "_", with: " ")] { return found }
        }
        if let codename, !codename.isEmpty, let found = devices[codename.lowercased()] { return found }
        return nil
    }
}
