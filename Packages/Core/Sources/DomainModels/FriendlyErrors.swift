import Foundation

/// Plain-language explanations for the failures adb reports most often, so a toast says what to do instead of quoting adb.
public enum FriendlyErrors {
    private static let rules: [(needle: String, text: String)] = [
        ("unauthorized", "This Mac is not allowed on the phone yet. Unlock the phone and tap Allow."),
        ("device offline", "The phone stopped responding. Unplug the cable, plug it in again and unlock the phone."),
        ("no devices/emulators found", "No phone is connected. Plug it in and turn on USB debugging."),
        ("device not found", "The phone was disconnected."),
        ("more than one device", "More than one phone is connected. Choose one in the list first."),
        ("INSTALL_FAILED_INSUFFICIENT_STORAGE", "The phone does not have enough free space for this app."),
        ("INSTALL_FAILED_OLDER_SDK", "This app needs a newer version of Android than the phone has."),
        ("INSTALL_FAILED_UPDATE_INCOMPATIBLE", "The app is already installed with a different signature. Uninstall it on the phone first."),
        ("INSTALL_FAILED_ALREADY_EXISTS", "The app is already installed."),
        ("INSTALL_PARSE_FAILED", "That file is not a valid app package."),
        ("INSTALL_FAILED_USER_RESTRICTED", "The phone blocks installs over USB. Turn on “Install via USB” in Developer options."),
        ("No space left on device", "The phone has no free space left."),
        ("Permission denied", "The phone refused access to that location."),
        ("Connection refused", "Nothing answered at that address. Check the address and that Wireless debugging is on."),
        ("failed to connect", "Could not reach the phone over Wi-Fi. Check that it is on the same network."),
        ("protocol fault", "The connection to the phone was interrupted. Try again."),
    ]

    /// Every sentence this can produce, so a test can check that each one is translated.
    public static var allTexts: [String] { rules.map(\.text) }

    /// The friendly text for a raw adb message, or nil when nothing matches (the raw text is then shown as is).
    public static func explain(_ raw: String) -> String? {
        rules.first { raw.localizedCaseInsensitiveContains($0.needle) }?.text
    }
}
