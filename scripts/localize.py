#!/usr/bin/env python3
"""Helpers for Resources/Localizable.xcstrings.

  localize.py export            numbered source strings, one per line:  N<TAB>english
  localize.py apply LANG FILE   FILE has lines  N<TAB>translation  (same numbering as export); checks placeholders, writes the catalog
  localize.py check             every language has every string, with the same placeholders as English
"""
import json, re, sys
PATH = 'Resources/Localizable.xcstrings'
PLACEHOLDER = re.compile(r'%(?:\d+\$)?(?:lld|ld|d|@|f|\.\df|s|u)')

def load():
    return json.load(open(PATH))

def keys(d):
    return list(d['strings'].keys())

def source_text(key, entry):
    en = (entry.get('localizations') or {}).get('en', {}).get('stringUnit', {}).get('value')
    return en if en is not None else key

def save(d):
    json.dump(d, open(PATH, 'w'), ensure_ascii=False, indent=2)
    open(PATH, 'a').write('\n')

def holders(text):
    return sorted(PLACEHOLDER.findall(text))

def export():
    d = load()
    for i, k in enumerate(keys(d)):
        text = source_text(k, d['strings'][k]).replace(chr(10), chr(92) + 'n')
        print(f"{i}\t{text}")

def apply(lang, file):
    d = load(); ks = keys(d); problems = 0; done = 0
    for line in open(file, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line.strip(): continue
        n, _, text = line.partition('\t')
        i = int(n); k = ks[i]; en = source_text(k, d['strings'][k])
        text = text.replace(chr(92) + 'n', chr(10))
        if holders(en) != holders(text):
            print(f"PLACEHOLDER MISMATCH {i}: {en!r} -> {text!r}"); problems += 1; continue
        d['strings'][k].setdefault('localizations', {})[lang] = {'stringUnit': {'state': 'translated', 'value': text}}
        done += 1
    save(d); print(f"{lang}: wrote {done}, skipped {problems}")

def check():
    d = load(); langs = set()
    for v in d['strings'].values(): langs |= set((v.get('localizations') or {}).keys())
    bad = 0
    for lang in sorted(langs - {'en'}):
        missing = [k for k, v in d['strings'].items() if lang not in (v.get('localizations') or {})]
        mism = [k for k, v in d['strings'].items() if lang in (v.get('localizations') or {}) and holders(source_text(k, v)) != holders(v['localizations'][lang]['stringUnit']['value'])]
        print(f"{lang}: missing {len(missing)}, placeholder mismatches {len(mism)}"); bad += len(missing) + len(mism)
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    cmd = sys.argv[1]
    {'export': export, 'check': check}.get(cmd, lambda: apply(sys.argv[2], sys.argv[3]))()
