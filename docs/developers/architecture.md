# Architecture

## Layout

```
BenzMirror.xcodeproj      thin app shell (generated from project.yml)
App/                      entry point, app delegate, dependency wiring
Resources/                Info.plist, entitlements, string catalogs, scrcpy server and licence, bundled keymaps, examples, device names
Packages/
  Core/                   DomainModels (settings, messages, keymaps, parsers)  ·  Persistence (profile files)
                          Media (video, audio, recording, TS muxer, AAC)  ·  Networking (adb, scrcpy session, OBS server, logging proxy)
                          AppInspection (gRPC client for Android Studio's profiler daemon)  ·  SystemServices (pointer lock, key capture)
  DesignSystem/           Theme: colours, type, spacing, glass and material surfaces
  Features/               WorkspaceFeature (windows, menus, per-phone session)  ·  KeymapFeature  ·  LogcatFeature  ·  InspectorFeature
                          DatabaseFeature  ·  SettingsFeature
  TestSupport/            helpers shared by the tests (snapshots, ffmpeg)
UITests/                  end-to-end smoke test
scripts/                  build-app.sh, test.sh, make-dmg.sh, install-local.sh, fetch-server.sh, localize.py, make-notices.py
website/                  the landing page (see release.md)
```

Dependencies only point downwards: Networking → Media → DomainModels → Persistence. DomainModels holds the pure logic and has the most tests.

## Technical notes

| Area | How |
|---|---|
| Mirroring | H.264/H.265 → `AVSampleBufferDisplayLayer` (hardware decoder), frames shown on arrival |
| Input | Click = touch, right click = Back, middle click = Home; typed text is injected; Shift, Option and Ctrl travel as meta state |
| Audio | Raw PCM (no decoder, no added latency); Android 11+ |
| Recording | MP4, video stored as-is, audio as AAC. A recording ends if the phone's screen size changes |
| Separate display | scrcpy `new_display` + `flex_display`; window size sent as RESIZE_DISPLAY (type 21); app opened with START_APP (type 16) |
| Clipboard | Text through the scrcpy control message; files through a small dex helper (`Tools/ClipHelper`) that sets a `content://` clip with `IClipboard.setPrimaryClip` |
| Wireless | `adb pair` (Android 11+) and `adb connect` |
| Keymaps | Profiles are JSON (`.benzkeymap`); positions are fractions of the screen; `KeymapEngine.plan(for:)` turns every element into macro steps |
| Phone-state safety | `PhoneChangeLedger` records what the app changed on the phone (proxy, Do Not Disturb, quick toggles) and restores it at the next session if the app died |
| Debug-app inspector | Pushes Android Studio's `transport` daemon, agent and network inspector, attaches the agent to a debuggable app (`BeginSession`), and reads HTTP events over gRPC. The protocol messages in `Packages/Core/Sources/AppInspection/Protos` are a trimmed copy (same field numbers) of the AOSP definitions |
| Languages | `AppLanguage` writes `AppleLanguages` as `[chosen, "en"]` so English is the fallback; a restart applies it |

## Security

- The scrcpy server runs on the phone as the `shell` user, so its SHA-256 is **pinned** and checked before each push (`ServerBundle`). `scripts/fetch-server.sh` refuses a mismatching download.
- Every listener (device link and OBS stream) binds to `127.0.0.1` only. The OBS server accepts only `GET`, caps request size, times out stalled clients, and drops viewers that fall behind.
- `adb` is run with an argument array, never a shell. Serials, wireless addresses, pairing codes, file names and server options are validated, sanitized or clamped. The pairing code goes through stdin so it is not visible in the process list.
- Packet sizes and frame dimensions from the device are bounded.
- Clipboard sync is off; content crosses only on an explicit action.
- The app is not sandboxed on purpose (it runs `adb` and pushes files to the phone). It is ad-hoc signed with the hardened runtime.

## Updating scrcpy

The wire protocol changes between releases and the server must match exactly. To upgrade, change `version` and `sha256` in `ServerBundle.swift` and `scripts/`, fetch the new server, and re-check the protocol notes in scrcpy's `doc/develop.md` against `ControlMessage.swift` and `ScrcpySession.swift`.
