#!/usr/bin/env python3
"""Writes Resources/THIRD-PARTY-NOTICES.txt from the packages pinned in Packages/Core/Package.resolved.
Run it after the dependencies change (the packages must be resolved: `swift package resolve` in Packages/Core)."""
import hashlib, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORE = os.path.join(ROOT, 'Packages/Core')
pins = json.load(open(os.path.join(CORE, 'Package.resolved')))['pins']

def license_path(identity):
    base = os.path.join(CORE, '.build/checkouts', identity)
    for name in ('LICENSE.txt', 'LICENSE', 'LICENSE.md', 'COPYING'):
        if os.path.exists(os.path.join(base, name)): return os.path.join(base, name)

texts, packages = {}, []
for pin in sorted(pins, key=lambda p: p['identity']):
    path = license_path(pin['identity'])
    version = pin['state'].get('version') or pin['state'].get('revision', '')[:7]
    if not path:
        raise SystemExit(f"no licence file for {pin['identity']}")
    body = open(path, encoding='utf-8', errors='replace').read().strip()
    key = hashlib.sha1(body.encode()).hexdigest()[:8]
    texts.setdefault(key, body)
    packages.append((pin['identity'], version, pin['location'], key))

keys = list(texts)
out = []
out.append("""THIRD-PARTY NOTICES
===================

Benz Mirror includes or uses the software below. Each package is used under the licence named next to it; the full texts follow the list.

scrcpy server 5.0.1 (Genymobile) — Apache License 2.0
  https://github.com/Genymobile/scrcpy
  The server runs on the phone and is bundled with the app. Its licence text is at the end of this file.

Profiler protocol definitions (The Android Open Source Project) — Apache License 2.0
  https://android.googlesource.com/platform/tools/base
  A trimmed copy of parts of the transport and app-inspection protocols is compiled into the app so it can talk to Android Studio's profiler daemon.

Android Studio components (Google) — not distributed with Benz Mirror
  Looking inside a debug app uses the transport daemon, agent and network inspector from the user's own Android Studio installation. They are read from there at run time and pushed to the phone; they are not part of this app.

Swift packages
--------------""")
for name, version, location, key in packages:
    out.append(f"  {name} {version}\n    {location}\n    licence text [{keys.index(key) + 1}]")
out.append("\nLicence texts\n-------------")
for i, key in enumerate(keys, 1):
    out.append(f"\n[{i}]\n{'-' * 60}\n{texts[key]}")
scrcpy = open(os.path.join(ROOT, 'Resources/LICENSE-scrcpy'), encoding='utf-8').read().strip()
out.append(f"\nscrcpy\n{'-' * 60}\n{scrcpy}\n")
open(os.path.join(ROOT, 'Resources/THIRD-PARTY-NOTICES.txt'), 'w', encoding='utf-8').write("\n".join(out))
print(f"{len(packages)} packages, {len(keys)} distinct licence texts")
