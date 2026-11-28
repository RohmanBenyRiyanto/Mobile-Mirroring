# Automated QA pass, 2026-11-28

Method: the installed Release app was driven through System Events (menu clicks, key presses) while the real phone (Samsung Galaxy S23, USB) was connected; window
sizes and positions were read back after every step. Live phone tests ran through `BENZMIRROR_TEST_SERIAL`. Unit tests (DesignSystem, Core, Features) ran after every change.

## Found and fixed

| # | Finding | Fix |
|---|---|---|
| 1 | After the app quit by closing its window, the next launch opened no phone window (only reopened helper windows). | Launch checks that a phone window exists and opens one; reopened helper windows are closed; state restoration off. |
| 2 | Opening the HUD, Quick Toggles or Inspector panel squeezed or covered the picture instead of widening the window. | The window's width is now the picture plus every open panel; it grows right, slides left only if the screen has no room. |
| 3 | Closing a panel left the window wide (it never shrank back). | The width without panels is remembered and restored exactly. |
| 4 | With a helper window focused (Database, Logcat), the panel toggle resized the helper window, not the phone window. | The phone window is tracked explicitly (`HostWindow`). |
| 5 | The phone window could hang off the bottom of the screen after mirroring started. | `WindowPlacement.fitted` keeps every resize on screen. |
| 6 | Leaving Stream Mode did not restore the window (371×835 became 356×803). | The frame before Stream Mode is stored and restored. |
| 7 | Logcat toolbar overflowed: the Restart button was cut off at 900 pt. | Icon buttons with tooltips, flexible filter, package label shrinks first. |
| 8 | Blurry separate display (native quality capped the display at 320 px). | Native means a 2560 px ceiling. |
| 9 | Device Information was empty before mirroring; Advanced could only be opened by its small arrow. | Info is read from the selected phone; the whole row opens it. |
| 10 | Values appeared from nothing (device list, device info, HUD, Quick Toggles). | Skeleton/spinner placeholders. |
| 11 | Rail icons had no usable tooltips (the system ones do not show on a non-key panel). | Own tooltip panel with name, shortcut and a description. |
| 12 | Disconnect from the rail ended the session without asking. | Confirmation (can be turned off). |

## Measured (Release app, mirroring, phone idle)

- Window sizes: Connect 760×564 at launch; phone window 371×835 on this screen; HUD +300, Quick Toggles +300, Inspector +320; modes never resize the window.
- CPU about 10 %, memory about 205 MB while mirroring.
- Live: USB gaming preset 52 fps / 5 ms jitter; Wi-Fi 47–49 fps, jitter 11 ms (gaming) to 34 ms (maximum).

## Still open

- Colours, spacing and Dark/Light looks were checked only from the user's screenshots; no pixel review of every screen.
- macOS 14–25 appearance not run (this Mac is on 26+).
- Trackpad scrolling, arrow-key scrolling and sound need hands-on use.
- UI tests (`UITests`) pass when the screen is awake; they cannot see windows while the display sleeps.

## Visual review (screenshots taken from the running app)

Reviewed: mirror window with rail, HUD, Quick Toggles, Logcat, API Log, Database, Settings (General, About), Connect, onboarding sheet, DMG window.

| Finding | Fix |
|---|---|
| HUD sparklines hugged the right edge and looked like stray marks; rows were too tall. | The line grows from the left across a 30-sample window and only appears with two samples; rows are compact. |
| API Log showed empty striped rows. | Empty state with an explanation. |
| Database: picker label right-aligned next to a left-aligned button; an error for the launcher shown on open. | Left aligned, no automatic open. Rewritten as a multi-database browser. |
| Onboarding sheet (620 pt) was taller than the Connect window (564 pt). | 480×470. |
| DMG icon names were unreadable on a dark background. | Light background. |

## Added from the review

- Logcat can follow any chosen app (not only the one in front), with a searchable app list.
- Database Inspector modelled on Android Studio's: every database of the app in one tree (Room's own tables dimmed), tabs for tables and queries, sort by header, paging, filter form, structure view, live updates, query templates, table/column insert menus, history, error hints, CSV export. Read-only by design.
