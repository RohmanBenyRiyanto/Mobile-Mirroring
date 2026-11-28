# Things that still need a real test

Tick a box when it has been tried by hand on a real phone and Mac. "Auto" means the logic has unit or live tests, but nobody has watched it work.

## Input and scrolling
- [ ] Trackpad two-finger scroll in Instagram, TikTok and a long list: smooth, flings on release, no double momentum.
- [ ] Arrow keys scroll (tap = one step, hold = steady pace, ← → in carousels). Option+arrow still moves a text cursor.
- [ ] Edit shortcuts with the picture focused: ⌘A, ⌘X, ⌘C, ⌘V, ⌘Z, ⇧⌘Z in a text field on the phone; Shift+arrows select; Option+Delete removes a word.
- [ ] ⌘A, ⌘C, ⌘V in Mac text fields (Logcat filter, Database query, Settings) still work normally.
- [ ] ⌘V with files copied in Finder: they land in Download and the notice names them.
- [ ] Dropping many files, a folder, an APK, an image: where each goes, notices, Gallery shows images and videos.
- [ ] Clipboard image (⌥⌘V) arrives and opens.

## Sound
- [ ] Phone sound on the Mac: no crackle at the default 120 ms buffer; buffer slider and Volume slider; output device switch.
- [ ] Backlog drop after a Mac stall (one short gap, then low delay).
- [ ] Microphone source on a phone that allows it; message when it does not.
- [ ] Audio in recordings on and off.

## Separate display and games
- [ ] Magic Chess: Go Go on the separate display: touches land, window turns landscape by itself, drag-resize stays sharp, no black bars at 19.5:9.
- [ ] The Magic Chess keymap, every key: 1–5 buy, D refresh, R lock, F XP, U buy all (timing), H hero list, bench Z X C V B N M ,. **The refresh button position differs between the user's old profile (0.94, 0.88) and the measured one (0.85, 0.50): check on the real match screen.**
- [ ] Keymap on the phone's own screen and on a separate display of another shape (positions drift).
- [ ] Rapid Tap and Swipe actions in a game (rate, path, fling).
- [ ] Controller: connect and disconnect notices, every binding, stick directions, works with the window in the background. Try Xbox, PlayStation and Switch Pro pads.
- [ ] Keymap editor: Controller section, Add Rapid Tap / Add Swipe, dragging the yellow swipe arrow, undo/redo (⌘Z goes to the editor while it is open).
- [ ] Auto switch by game and macro recording still behave.
- [ ] Do Not Disturb (rail button and Quick Toggles): silences, and is switched off again on disconnect.

## Window and layout (every mode)
- [ ] Panels (HUD, Quick Toggles, Inspector, keymap editor) extend the window to the right and shrink back exactly, alone and together.
- [ ] Same with the window near the right edge of the screen, on an external display, on a small laptop screen, in full screen, in another Space.
- [ ] Switch Normal / Gaming / Developer with panels open; Stream Mode on and off; minimize and restore (the rail goes and returns).
- [ ] Phone window size and place after Connect → mirror → Disconnect → mirror again, and after quitting and reopening.
- [ ] Mini mirror: hover controls, always on top, follows rotation, two phones.
- [ ] Rail tooltips near screen edges and on a second display; the collapsed rail.

## Safety net for the phone
- [ ] Kill the app (`kill -9`) with Quick Toggles, mock location, Wi-Fi off and the API proxy active; reconnect: everything is put back and a notice appears.
- [ ] Pull the cable with a change active; reconnect.
- [ ] Reboot the phone with a change active; reconnect (nothing applied twice).
- [ ] Two phones at once: each one's changes are tracked separately.
- [ ] Wireless connection: Wi-Fi switches are not offered; the connection-lost dialog retries and gives up properly.

## Developer tools
- [ ] API Log with a real app: HTTP headers, bodies (JSON, gzip, chunked), Copy as cURL, status colours; HTTPS shows only the address. Proxy removed after switching off, after quit, after kill.
- [ ] Database inspector on a Room debug app: all databases in the tree, system tables dimmed, sort, paging, filter form, structure, live updates while the app writes, query templates and history, a large table, a WAL database, an encrypted one (message).
- [ ] Logcat: Choose an app (earlier lines appear), App in front, Everything; crash blocks; toolbar at the minimum width.
- [ ] Inspector panel on a real screen; Quick Toggles effects visible (layout bounds, overdraw, animation speed, dark mode); mock location in a maps app.
- [ ] HUD with a game (frame rate may show none), thermal warning.

## Confirmations
- [ ] Start recording, dropped APK install, Wi-Fi/mobile data off, discard keymap changes, disconnect: wording, buttons, "Don't ask again", and the Settings switches that bring them back.
- [ ] Quit while recording; close the window while recording.

## Recording and capture
- [ ] Recording with sound, long recordings, rotation mid-recording, a full disk; GIF export of a trimmed clip; screenshot folder choice.
- [ ] OBS: the stream URL as a Media Source.

## Install and first run
- [ ] DMG on a Mac that never ran the app: the "Open anyway" steps in the README match what macOS shows; the DMG window looks right in Light and Dark.
- [ ] Fresh defaults: welcome sheet, Setup Guide from the Connect banner and Help menu; the bundled Magic Chess keymap appears once and a deleted one is not restored.
- [ ] A different phone model: device names, Android 11–14 behaviour (audio, mock location, virtual display).

## Looks and language
- [ ] Light mode of every screen; macOS 14–25 (no Liquid Glass) and macOS 26+; accent colours; Reduce Motion; Increase Contrast.
- [ ] Indonesian: no clipped text in buttons, tabs, the rail tooltips and dialogs.
- [ ] VoiceOver and keyboard-only use of Connect, Settings, the rail and the panels.

## Performance
- [ ] A one-hour mirroring session in the Release build: memory stays flat, CPU stays low, no frame-rate drift.
- [ ] Wi-Fi presets: Balanced and Game streaming are steady, Maximum warns.

## Planned features that will need their own tests
- [ ] Pasting copied files into a chat (WhatsApp, Telegram) through the phone clipboard, and the "send to the app in front" fallback (see the research note in the conversation; not built yet).
- [ ] Decrypting HTTPS for debug apps (not built; needs a certificate or an agent like Android Studio's).
