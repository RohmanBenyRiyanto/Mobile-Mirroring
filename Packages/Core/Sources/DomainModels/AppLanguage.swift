import Foundation

public struct AppLanguage: Equatable, Identifiable, Sendable {
    public let code: String
    public var id: String { code }

    public init(_ code: String) { self.code = code }

    public static let supported: [AppLanguage] = ["en", "id", "es", "fr", "de", "pt-BR", "zh-Hans", "ja", "ko", "ru", "tr"].map(AppLanguage.init)

    public static let overrideKey = "benzmirror.languageOverride"
    private static let systemKey = "AppleLanguages"

    public var nativeName: String {
        if let name = Self.names[code] { return name }
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code) ?? code
    }

    static let names: [String: String] = [
        "en": "English", "id": "Bahasa Indonesia", "es": "Español", "fr": "Français", "de": "Deutsch", "pt-BR": "Português (Brasil)",
        "ru": "Русский", "ja": "日本語", "ko": "한국어", "zh-Hans": "简体中文", "zh-Hant": "繁體中文", "ar": "العربية", "hi": "हिन्दी",
        "tr": "Türkçe", "vi": "Tiếng Việt", "th": "ไทย", "it": "Italiano", "nl": "Nederlands", "pl": "Polski", "uk": "Українська",
        "ms": "Bahasa Melayu", "bn": "বাংলা", "fa": "فارسی", "he": "עברית", "sv": "Svenska", "cs": "Čeština", "el": "Ελληνικά",
        "ro": "Română", "hu": "Magyar", "da": "Dansk", "fi": "Suomi", "nb": "Norsk bokmål", "fil": "Filipino",
    ]

    public static func chosen(in defaults: UserDefaults = .standard) -> AppLanguage? {
        guard let code = defaults.string(forKey: overrideKey), supported.contains(where: { $0.code == code }) else { return nil }
        return AppLanguage(code)
    }

    public static func preferenceList(for choice: AppLanguage?) -> [String]? {
        guard let choice else { return nil }
        return choice.code == "en" ? ["en"] : [choice.code, "en"]
    }

    public static func choose(_ choice: AppLanguage?, in defaults: UserDefaults = .standard) {
        if let list = preferenceList(for: choice), let choice {
            defaults.set(choice.code, forKey: overrideKey)
            defaults.set(list, forKey: systemKey)
        } else {
            defaults.removeObject(forKey: overrideKey)
            defaults.removeObject(forKey: systemKey)
        }
    }

    public static func needsRestart(started: AppLanguage?, now: AppLanguage?) -> Bool { started != now }
}
