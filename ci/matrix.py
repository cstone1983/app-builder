#!/usr/bin/env python3
"""Prints the build matrix for GitHub Actions: `matrix=<json>` for the apps asked for.

Env: APP = an app id from apps.json, a comma list, or "all"; REF = optional ref override (only
allowed with a single app). Fails on an unknown id so a typo never builds nothing silently.
"""
import json, os, re, sys

apps = json.load(open(os.path.join(os.path.dirname(__file__), "..", "apps.json")))["apps"]
want = (os.environ.get("APP") or "all").strip()
ref = (os.environ.get("REF") or "").strip()

ids = [a["id"] for a in apps]
pick = ids if want == "all" else [w.strip() for w in want.split(",") if w.strip()]
bad = [p for p in pick if p not in ids]
if bad or not pick:
    sys.exit(f"unknown app id(s) {bad or want!r}; known: {', '.join(ids)}")
if ref:
    if len(pick) != 1:
        sys.exit("a ref override needs exactly one app")
    if not re.fullmatch(r"[A-Za-z0-9._/-]{1,200}", ref):
        sys.exit("ref has unexpected characters")

out = []
for a in apps:
    if a["id"] not in pick:
        continue
    a = dict(a)
    a.pop("_comment", None)
    if ref:
        a["ref"] = ref
    a.setdefault("dir", ".")
    a.setdefault("prepare", "")
    a.setdefault("cache_paths", "")
    a.setdefault("cache_key_files", "")
    a.setdefault("flutter", "")
    out.append(a)

print("matrix=" + json.dumps(out, separators=(",", ":")))
