#!/usr/bin/env python3
"""Fails if code uses a string key missing from any ARB file, or if an ARB
file is missing keys present in the English template. Run in CI."""
import glob
import json
import re
import sys

used = set()
for path in glob.glob("lib/**/*.dart", recursive=True):
    if "/l10n/gen/" in path:
        continue
    used |= set(re.findall(r"\bl10n\.([a-zA-Z0-9_]+)", open(path, encoding="utf-8").read()))
used.discard("dart")

template = json.load(open("lib/l10n/app_en.arb", encoding="utf-8"))
keys = {k for k in template if not k.startswith("@")}
problems = []
missing = sorted(used - keys)
if missing:
    problems.append(f"app_en.arb is missing keys used in code: {missing}")
for path in sorted(glob.glob("lib/l10n/app_*.arb")):
    if path.endswith("app_en.arb"):
        continue
    data = json.load(open(path, encoding="utf-8"))
    gap = sorted(keys - set(data))
    if gap:
        problems.append(f"{path} is missing {len(gap)} keys: {gap[:10]}")
    for k, v in data.items():
        if k.startswith("@") or k not in template:
            continue
        declared = template.get("@" + k, {}).get("placeholders", {})
        for name in declared:
            if not re.search(r"\{" + re.escape(name) + r"[,}]", v):
                problems.append(f"{path}: {k} is missing placeholder {{{name}}}")
print("\n".join(problems) if problems else f"l10n ok: {len(keys)} keys, {len(used)} used in code")
sys.exit(1 if problems else 0)
