# Benz Mirror

> **Beta.** This is the first beta (0.1.0 beta 1). It has been tried mostly on one phone; expect rough edges, and please report what you find.

Native macOS app that mirrors and controls an Android phone, built on the scrcpy server (v5.0.1).
The client side (protocol, hardware video decoding, audio, recording, streaming, input) is written in Swift.
Nothing is installed on the phone.

## Install (DMG)

1. Download `Benz-Mirror-<version>.dmg` from the Releases page, open it and drag **Benz Mirror** to Applications.
2. Install `adb` once: `brew install android-platform-tools`.
3. The first launch is blocked by macOS because the app is not notarized (it is signed ad-hoc, with no paid Apple Developer ID).
   Try to open it once, then go to System Settings → Privacy & Security and choose **Open Anyway** (on macOS 14 you can also right-click the app → **Open**). This is needed only once.
4. Turn on USB debugging on the phone and plug it in. The welcome screen walks through it.

Build the DMG yourself with `scripts/make-dmg.sh`. With a Developer ID later:
`SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=<keychain profile> scripts/make-dmg.sh` signs and notarizes it.

## What it does

- Mirror and control the phone with hardware video decoding; sound plays on the Mac (or use the phone's microphone).
- **Smooth scrolling:** trackpad and arrow keys scroll like a finger, so feeds fling naturally.
- **Separate display:** mirror one app on a display that follows the window size, with no black bars.
- Modes (Normal, Gaming, Developer) with a customizable control rail, keymaps for games, macros, recording and GIF export.
- Developer tools: performance HUD, quick toggles, mock location, Wi-Fi/data switches, database viewer, API call log, UI inspector, Logcat.
- OBS output, wireless setup, multiple phones, mini mirror.
- Looks inside a debug app to show the contents of its HTTP and HTTPS calls (needs Android Studio on the Mac; no certificate on the phone).
- Thirteen languages (English, Bahasa Indonesia, Español, Français, Deutsch, Português, 简体中文, 日本語, 한국어, Русский, Türkçe, Italiano, Tiếng Việt), chosen in Settings; anything missing falls back to English.

## Run

```bash
./scripts/build-app.sh && open "build.noindex/Benz Mirror.app"   # release build, ad-hoc signed
open BenzMirror.xcodeproj                                # or work in Xcode: ⌘R to run, ⌘U for the UI tests
./scripts/test.sh                                        # unit tests of every package
BENZMIRROR_TEST_SERIAL=<adb serial> ./scripts/test.sh    # …plus the tests that use a real phone
```

Requirements: macOS 14+ (the full Liquid Glass look needs macOS 26+; older versions get the same layout with plain materials),
Xcode, `adb` (`brew install android-platform-tools`), USB debugging enabled on the phone.
`brew install xcodegen` is only needed to regenerate `BenzMirror.xcodeproj` from `project.yml` (run `scripts/generate-project.sh`, which also keeps Xcode's build output in `build.noindex/`). No CocoaPods: everything is Swift Package Manager.

## Quality presets

| Preset | Resolution | Bitrate | FPS | Codec | Key frames |
|---|---|---|---|---|---|
| Balanced | up to 1920 px | 8 Mbps | 60 | H.264 | 10 s |
| High quality | native | 20 Mbps | 60 | H.264 | 2 s |
| **Game streaming** | native | 40 Mbps, constant | 60 | H.264 | 1 s |
| Maximum | native | 80 Mbps, constant | 120 | H.265 | 1 s |

Everything is adjustable under *Advanced* (up to 200 Mbps, 120 fps, 4096 px). Your choice is remembered.
Use USB for the higher presets; Wi-Fi is fine for Balanced and High.

## Streaming to OBS

Two ways, pick what suits you:

**1. Local stream (best quality, no re-encoding).** Tick *Stream to OBS* before starting. Benz Mirror re-serves the phone's
own H.264/H.265 + AAC as an MPEG transport stream on `127.0.0.1` only. In OBS:

1. Sources → **+** → **Media Source**
2. Untick *Local File*
3. Input: `http://127.0.0.1:8765/live.ts` (⇧⌘C copies the URL) · Input Format: `mpegts`
4. Network Buffering: **0 MB** (lowest delay). Optionally untick *Use hardware decoding* if you see artifacts.

A viewer always starts on a key frame, and each new viewer asks the phone for one immediately, so OBS shows a picture right away.

**2. Window capture.** *Stream Mode* (⇧⌘S) turns the window into a clean, aspect-locked frame with no title bar or controls.
Add it to OBS with *macOS Screen Capture* → *Window*. ⌘1 sizes it to 1 video pixel = 1 screen pixel. *Always on Top* (⇧⌘T) keeps it visible.

## Features

| Feature | How |
|---|---|
| Mirror, low latency | H.264/H.265 → `AVSampleBufferDisplayLayer` (hardware decoder), frames shown on arrival |
| Live statistics | fps, Mbps, resolution, OBS viewers (⌘I) |
| Touch / scroll / keyboard | Click = touch, right click = Back, middle click = Home, typed text is injected |
| Pinch zoom / rotate | Trackpad pinch, or hold **Option** and drag |
| Audio | Raw PCM (no decoder, no added latency); Android 11+ |
| Screen recording | MP4 in `~/Movies/Benz Mirror`; video stored as-is, audio as AAC |
| Screenshot | `~/Pictures/Benz Mirror` |
| Drag & drop | `.apk` is installed, any other file goes to the phone's Download folder |
| Clipboard | ⌘V pastes to the phone, ⌘C copies from it (never automatic) |
| Wireless | One-click switch to Wi-Fi, `adb pair` (Android 11+) and `adb connect` |
| Game keymaps | Keyboard and mouse to touch: buttons, joystick, free-look, skill-shots (see below) |
| Logcat | Live window (⌘L): follows the app in front (or everything), level and text filters, pause, copy; crashes, ANRs and stack traces are highlighted as blocks with a crash counter |
| Device menu | Dark mode, animations on/off, pointer location |
| Control rail | Back, Home, Recents, volume, power, notifications, quick settings, rotate |

A recording ends if the phone's screen size changes (rotation), since a file cannot change frame size.

## Keyboard and mouse mapping (games)

Menu **Keymap** (⌘K switches it on). A keymap is a profile: a list of elements placed on the phone's screen as fractions
(0…1), so it fits any phone. Elements:

| Element | What it does |
|---|---|
| Button — tap | A quick touch each time the key is pressed |
| Button — hold | The finger stays down while the key is held (fire) |
| Button — toggle | One press puts the finger down, the next lifts it |
| Joystick | WASD (or any four keys) steer a virtual analog stick, with smooth start and stop |
| Aim / free-look | A key captures the mouse; moving it turns the camera, endlessly |
| Mouse button | Left or right click as a touch, only while aiming |
| Skill-shot | Hold to aim at the mouse, release to cast (or cast at once) |
| Macro | Record real touches with their timing (**Keymap → Record Macro**, ⇧⌘M), then replay them from one key; optional loop while held |

Keys that the keymap uses are taken by the game; every other key still types. Fingers are always lifted when the window loses focus,
the phone rotates or the keymap is switched off. Profiles live in `~/Library/Application Support/Benz Mirror/Profiles/keymap`
and can be shared (below). Give a keymap the game's package name (editor → *Use app in front*) and it
switches on by itself when that game opens, and off again when you leave (settings: *Switch keymaps by game*). `Resources/Examples/example.benzkeymap` shows every element; positions are only an
example, so adjust them for your game, or just open the editor.

**Sharing.** A keymap is a `.benzkeymap` file (JSON). Export it (**Keymap → Export Current Keymap…**) or copy it as text
(**Copy Current Keymap**) and send it to a friend. To import: **Import Keymap…**, **Import from Clipboard…**, drag the file onto the
mirror, or double-click it in Finder. Nothing from outside is saved silently: you first see what it contains (buttons, joysticks, recorded
macros, the game it will switch on for) and confirm. An existing keymap is never overwritten; a clash is saved as a copy.

**Editor** (Keymap → Edit Keymap…, ⌘E): drag each element onto the phone's screen, click a key button and press the key you want, use the
inspector for reach, sensitivity and behavior, and Save. While the editor is open nothing you click or type reaches the phone.

## Layout

```
BenzMirror.xcodeproj      thin app shell (generated from project.yml)
App/                      entry point, app delegate, dependency wiring
Resources/                Info.plist, entitlements, scrcpy server + licence
Packages/
  Core/                   DomainModels (settings, messages, keymaps, parsers)  ·  Persistence (profile files)
                          Media (video, audio, recording, TS muxer, AAC)  ·  Networking (adb, scrcpy session, OBS server)
                          SystemServices (pointer lock, key capture)
  DesignSystem/           Theme: colours, type, spacing, glass / material surfaces
  Features/               WorkspaceFeature (windows, menus, per-phone session)  ·  KeymapFeature  ·  LogcatFeature  ·  InspectorFeature
  TestSupport/            helpers shared by the tests (snapshots, ffmpeg)
UITests/                  end-to-end smoke test
Resources/                Info.plist, entitlements, string catalog, bundled keymaps, examples, device names
(docs/ is git-ignored: notes, QA lists and design sources stay local; un-ignore one with a !docs/<file> line in .gitignore)
scripts/                  build-app.sh, test.sh, fetch-server.sh
```

## Security

- The scrcpy server runs on the phone as the `shell` user, so its SHA-256 is **pinned** and checked before each push (`ServerBundle`). `scripts/fetch-server.sh` refuses a mismatching download.
- Every listener (device link and OBS stream) binds to `127.0.0.1` only; nothing is exposed to the network. The OBS server accepts only `GET`, caps request size, times out stalled clients, and drops viewers that fall behind.
- `adb` is run with an argument array (never a shell). Serials, wireless addresses, pairing codes, file names and server options are validated, sanitized or clamped; the pairing code goes through stdin so it is not visible in the process list.
- Packet sizes and frame dimensions from the device are bounded.
- Clipboard sync is off; content crosses only on an explicit action.
- The app is ad-hoc signed with the hardened runtime. Server licence: Apache 2.0 (`Resources/LICENSE-scrcpy`).

## Updating scrcpy

The wire protocol changes between releases and the server must match exactly. To upgrade, change `version`
and `sha256` in `ServerBundle.swift` and `scripts/`, fetch the new server, and re-check the protocol notes in
scrcpy's `doc/develop.md` against `ControlMessage.swift` and `ScrcpySession.swift`.

## Beta notes

- Tested so far on a Samsung Galaxy S23 (Android 17). Other phones and Android versions are not verified yet.
- The translations were written without review by native speakers.
- No app is installed on the phone. Small helper files are pushed to `/data/local/tmp` (the scrcpy server, a clipboard helper, and, for the debug-app view, Android Studio's profiler files); pasted files wait in `Download/Benz Mirror Paste` until the session ends.
- The app collects nothing and sends nothing anywhere. It talks to your phone through `adb` and, for the optional debug-app view, to the profiler that ships with your own Android Studio.
- Third-party licences are in `Resources/THIRD-PARTY-NOTICES.txt` and under Settings › About › Licenses.
