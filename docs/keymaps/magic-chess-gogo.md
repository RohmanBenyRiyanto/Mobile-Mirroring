# Magic Chess: Go Go keymap

File: `docs/examples/magic-chess-gogo.benzkeymap` (also installed as *Magic Chess: Go Go* in Keymap → Profile; built by `scripts/keymaps/magic-chess-gogo.py`). Game package: `com.mobilechess.gp`, so it switches on by itself when the game opens.

| Key | Action |
|---|---|
| 1 2 3 4 5 | Buy the shop hero in that place (left to right) |
| D | Refresh the shop |
| R | Lock / unlock the shop |
| F | Buy XP |
| U | Buy every hero in the shop (taps the five cards one after another) |
| H | Hero list |
| Z X C V B N M , | Select the hero on bench circle 1–8 (opens its details) |

D, R, F and U follow the LDPlayer default scheme for this game (source: LDPlayer's Magic Chess: Go Go keyboard mapping page), so emulator habits carry over. Buying with 1–5 was a request.

## How the positions were found

Measured on a screenshot of a live match (phone screen 2340×1080, shop open): the five shop cards, refresh, lock, buy-XP circle, hero list and the eight bench circles. Nothing about the layout was guessed from other games.

## Limits to know

- **Screen shape.** Positions are fractions of the picture. They match the phone's own landscape screen (19.5:9). With *Use a separate display* and a window of another shape, the game moves its buttons and the fractions no longer land on them. Keep the window close to 19.5:9, or mirror the phone's own screen.
- **Not mapped** (positions unknown, no public source): the commander joystick, commander skill, inventory, sell, view of other players, emote, surrender. Add them with Keymap → Edit Keymap by dragging a chip onto the button.
- **Gamepad.** This is a keyboard keymap. Reading a physical controller is not built.
