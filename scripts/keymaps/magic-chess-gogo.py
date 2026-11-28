#!/usr/bin/env python3
"""Builds the Magic Chess: Go Go keymap (docs/examples/magic-chess-gogo.benzkeymap).

Positions are fractions of the landscape picture. They were measured on a 2340×1080 screenshot of a match (the shop open):
shop cards 5, refresh, lock, buy-XP circle, hero list and the bench circles. Mac virtual key codes: see KeyNames.swift.
"""
import json, uuid, datetime, sys

W, H = 2340, 1080
SHOT = 2000  # the screenshot used for measuring was shown 2000 px wide; heights scale with the same factor
def pos(x, y):  # x, y measured on the 2000×923 view of the screenshot
    return {"x": round(x / 2000, 4), "y": round(y / 923, 4)}

KEY = {"1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "D": 2, "F": 3, "H": 4, "Space": 49, "Tab": 48,
       "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "U": 32, "N": 45, "M": 46, ",": 43, "Q": 12, "W": 13, "E": 14, "R": 15, "T": 17, "A": 0, "S": 1, "G": 5}

def button(label, key, point, mode="tap"):
    return {"id": str(uuid.uuid4()).upper(), "label": label, "position": point, "action": {"button": {"key": KEY[key], "mode": mode}}}

elements = []
# 1-5 buy the shop cards left to right (the number matches the card). The rest follows the LDPlayer default scheme:
# D refresh, R lock/unlock, F buy XP, U buy every hero in the shop.
CARD_X = [510, 754, 997, 1241, 1485]
for i, x in enumerate(CARD_X, start=1):
    elements.append(button(f"Buy hero {i}", str(i), pos(x, 330)))
elements += [
    button("Refresh shop", "D", pos(1692, 465)),
    button("Lock shop", "R", pos(310, 485)),
    button("Buy XP", "F", pos(140, 840)),
    button("Hero list", "H", pos(1662, 300)),
]
# U: a macro that taps the five cards one after another.
steps = []
for index, x in enumerate(CARD_X):
    point = pos(x, 330)
    t = index * 0.12
    steps.append({"time": round(t, 3), "kind": "down", "finger": 0, "position": point})
    steps.append({"time": round(t + 0.05, 3), "kind": "up", "finger": 0, "position": point})
elements.append({"id": str(uuid.uuid4()).upper(), "label": "Buy all heroes", "position": pos(997, 330),
                 "action": {"macro": {"key": KEY["U"], "steps": steps, "loop": False, "speed": 1.0}}})
# Bench: the bottom row Z X C V B N M , selects the hero on each of the 8 bench circles (its details open, with the sell button).
for key, x in zip(["Z", "X", "C", "V", "B", "N", "M", ","], [530, 664, 800, 935, 1069, 1203, 1337, 1471]):
    elements.append(button(f"Bench {key}", key, pos(x, 785)))

profile = {
    "format": "benzmirror.profile", "id": "magic-chess-gogo", "kind": "keymap", "version": 1, "name": "Magic Chess: Go Go",
    "modified": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "payload": {"package": "com.mobilechess.gp", "elements": elements},
}
json.dump(profile, open(sys.argv[1] if len(sys.argv) > 1 else "docs/examples/magic-chess-gogo.benzkeymap", "w"), indent=2, sort_keys=True)
print(len(elements), "elements")
