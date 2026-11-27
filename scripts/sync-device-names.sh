#!/bin/zsh
# Keeps Resources/DeviceNames.json in step with Google's public list of Android devices.
# One cheap conditional request first; the list is only downloaded and rebuilt when it changed.
# A failed or offline request never fails the build: the file already in the repository is kept.
set -u

URL="https://storage.googleapis.com/play_public/supported_devices.csv"
ROOT="${0:A:h:h}"
OUT="$ROOT/Resources/DeviceNames.json"
STATE="$ROOT/Resources/DeviceNames.state.json"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

state_value() { [[ -f "$STATE" ]] && python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$STATE" "$1" 2>/dev/null; }

etag="$(state_value etag)"
modified="$(state_value lastModified)"
args=(-sS --max-time 20 -D "$WORK/headers" -o "$WORK/list.csv")
[[ -n "$etag" ]] && args+=(-H "If-None-Match: $etag")
[[ -n "$modified" && -z "$etag" ]] && args+=(-H "If-Modified-Since: $modified")

if [[ -f "$OUT" ]] && ! curl "${args[@]}" -w '%{http_code}' "$URL" > "$WORK/code" 2>/dev/null; then
  echo "note: device names not refreshed (offline); keeping the existing list"; exit 0
fi
code="$(cat "$WORK/code" 2>/dev/null)"
if [[ ! -f "$OUT" ]]; then
  curl "${args[@]}" -w '%{http_code}' "$URL" > "$WORK/code" 2>/dev/null || { echo "note: device names unavailable"; exit 0; }
  code="$(cat "$WORK/code")"
fi
if [[ "$code" == "304" ]]; then echo "device names: not modified"; exit 0; fi
if [[ "$code" != "200" ]]; then echo "note: device names not refreshed (HTTP $code); keeping the existing list"; exit 0; fi

python3 - "$WORK/list.csv" "$WORK/headers" "$OUT" "$STATE" <<'PY' || { echo "note: device names could not be rebuilt; keeping the existing list"; exit 0; }
import csv, hashlib, json, sys

csv_path, headers_path, out_path, state_path = sys.argv[1:5]
raw = open(csv_path, "rb").read()
digest = hashlib.sha256(raw).hexdigest()
text = raw.decode("utf-16" if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8-sig")
rows = list(csv.DictReader(text.splitlines()))

headers = {}
for line in open(headers_path, encoding="latin-1"):
    if ":" in line:
        k, v = line.split(":", 1)
        headers[k.strip().lower()] = v.strip()

try:
    old = json.load(open(state_path))
except Exception:
    old = {}
if old.get("rows") == len(rows) and old.get("sha256") == digest:
    print("device names: unchanged")
    sys.exit(0)

def title(row):
    brand, name = row["Retail Branding"].strip(), row["Marketing Name"].strip()
    if not name:
        return None
    return name if brand and name.lower().startswith(brand.lower()) else (f"{brand} {name}" if brand else name)

models, devices = {}, {}
for row in rows:
    shown = title(row)
    if not shown:
        continue
    models.setdefault(row["Model"].strip().lower(), shown)
    devices.setdefault(row["Device"].strip().lower(), set()).add(shown)

# A device code shared by different marketing names would give a wrong answer, so only unambiguous ones are kept.
codes = {code: next(iter(names)) for code, names in devices.items() if len(names) == 1 and code}
json.dump({"models": models, "devices": codes}, open(out_path, "w"), ensure_ascii=False, separators=(",", ":"), sort_keys=True)
json.dump({"etag": headers.get("etag", ""), "lastModified": headers.get("last-modified", ""), "rows": len(rows), "sha256": digest},
          open(state_path, "w"), indent=2)
print(f"device names: rebuilt from {len(rows)} rows")
PY
