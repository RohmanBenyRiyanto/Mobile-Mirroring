# Benz Mirror

> **Beta.** This is the first beta (0.1.0 beta 1). It has been tried mostly on one phone, so expect rough edges, and please report what you find.

Benz Mirror shows your Android phone on your Mac and lets you control it with the mouse and keyboard. You can play games with keyboard mappings, record the screen, stream to OBS, and (for app developers) look at logs, databases and network calls. Nothing is installed as an app on the phone.

Website: <https://rohmanbenyriyanto.github.io/Mobile-Mirroring/>

## Install

1. Download `Benz-Mirror-<version>.dmg` from the Releases page, open it and drag **Benz Mirror** to Applications.
2. Install `adb` once: `brew install android-platform-tools`.
3. The first time, macOS blocks the app because it is not notarized. Try to open it once, then go to System Settings → Privacy & Security and choose **Open Anyway** (on macOS 14 you can also right-click the app → **Open**). This is needed only once.
4. Turn on USB debugging on the phone and plug it in. The welcome screen walks you through it.

Needs macOS 14 or later (the full Liquid Glass look needs macOS 26 or later) and an Android phone with Android 5.0 or later (sound needs Android 11 or later).

## What it does

- **Mirror and control** the phone with hardware video decoding. Sound plays on the Mac, or use the phone's microphone.
- **Smooth scrolling:** the trackpad and arrow keys scroll like a finger.
- **Separate display:** mirror one app on a display that follows the window size, with no black bars.
- **Modes:** Normal, Gaming and Developer, each with its own control rail (horizontal for landscape games).
- **Games:** keyboard and mouse maps, macros, rapid tap, swipes and game controllers.
- **Files:** drop an `.apk` to install it, or copy a file in Finder and paste it into a phone app such as WhatsApp with ⌘V.
- **Recording:** screen recording to MP4, GIF export and screenshots.
- **OBS:** send the picture to OBS, or use Stream Mode for a clean window.
- **Developer tools:** performance HUD, quick toggles (dark mode, animations, mock location, Wi-Fi and data, network speed), Logcat, UI inspector, database viewer and an API call log.
- **Debug apps:** look inside a debug build to see the contents of its HTTP and HTTPS calls. This needs Android Studio on the Mac and no certificate on the phone.
- **Wireless setup,** several phones at once and a Mini Mirror window.
- **Thirteen languages,** chosen in Settings (English, Bahasa Indonesia, Español, Français, Deutsch, Português, 简体中文, 日本語, 한국어, Русский, Türkçe, Italiano, Tiếng Việt). Anything missing shows in English.
- **Your own shortcuts:** every menu shortcut can be changed in Settings.

## Quality presets

| Preset | Resolution | Bitrate | FPS | Codec |
|---|---|---|---|---|
| Balanced | up to 1920 px | 8 Mbps | 60 | H.264 |
| High quality | native | 20 Mbps | 60 | H.264 |
| **Game streaming** | native | 40 Mbps, steady | 60 | H.264 |
| Maximum | native | 80 Mbps, steady | 120 | H.265 |

Everything can be adjusted under *Advanced*. Use USB for the higher presets; Wi-Fi is fine for Balanced and High quality.

## Streaming to OBS

**1. Local stream (best quality, no re-encoding).** Turn on *Send picture to OBS* before starting. In OBS:

1. Sources → **+** → **Media Source**
2. Turn off *Local File*
3. Input: `http://127.0.0.1:8765/live.ts` (⇧⌘C copies the address) · Input Format: `mpegts`
4. Network Buffering: **0 MB** for the lowest delay. If you see artifacts, turn off *Use hardware decoding*.

The stream is only available on your own Mac.

**2. Window capture.** *Stream Mode* (⇧⌘B) turns the window into a clean frame with no title bar or controls. Add it to OBS with *macOS Screen Capture* → *Window*.

## Game keymaps

Open the **Keymap** menu. A keymap places controls on the phone's screen, so it fits any phone:

| Control | What it does |
|---|---|
| Tap | A quick touch each time the key is pressed |
| Hold | The finger stays down while the key is held (fire) |
| Toggle | One press puts the finger down, the next lifts it |
| Joystick | WASD (or any four keys) steer a virtual stick |
| Aim | A key captures the mouse so moving it turns the camera |
| Skill shot | Hold to aim with the mouse, release to cast |
| Rapid tap | Hold the key to keep tapping a spot |
| Swipe | One key performs a swipe |
| Macro | Record real touches, then replay them from one key |

Open the editor with **Keymap → Edit Keymap** (⌘E): drag each control onto the phone's screen, click a key button and press the key you want, then save. Give a keymap the game's package (*Use app in front*) and it switches on by itself when that game opens.

Keymaps are shared as `.benzkeymap` files: export one, send it, and import it with **Import** or by dropping the file onto the mirror. You always see what a file contains before it is saved, and nothing is overwritten.

## Privacy and safety

- The app collects nothing and sends nothing to anyone. It talks to your phone through `adb`.
- Streams and links stay on your own Mac (`127.0.0.1`). The clipboard is never copied by itself, only when you ask.
- Small helper files are placed in `/data/local/tmp` on the phone while you use the app. Files you paste wait in `Download/Benz Mirror Paste` until the session ends.
- The phone's own settings that the app changes (proxy, Do Not Disturb, quick toggles) are put back when you disconnect, or the next time you connect if the app was closed unexpectedly.

## Beta notes

- Tested so far on a Samsung Galaxy S23 (Android 17). Other phones and Android versions are not verified yet.
- Third-party licences are in Settings › About › Licenses.

## For developers

Building, tests, architecture, releasing and translations are in [docs/developers](docs/developers/README.md).

## License

Benz Mirror is released under the Apache License 2.0 (see `LICENSE` and `NOTICE`). Copyright 2026 Rohman Beny Riyanto.
