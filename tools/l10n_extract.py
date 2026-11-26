#!/usr/bin/env python3
"""Builds Localization/en.json from the compiler's .stringsdata files.

Usage: tools/l10n_extract.py <dir with .stringsdata files>   (searched recursively)
Each entry: {"en": text or {plural forms}, "where": "File.swift:line", "line": source line,
"table": "AppShortcuts" for Siri phrases}. Plural forms, skipped keys, skipped files
and notes come from Localization/notes.json and are kept across runs.
"""
import glob, json, os, sys

src_dir = sys.argv[1]
repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
notes_path = os.path.join(repo, "Localization", "notes.json")
notes = json.load(open(notes_path, encoding="utf-8")) if os.path.exists(notes_path) else {}
skip = set(notes.get("_skip", []))
skip_files = set(notes.get("_skipFiles", []))
plural = notes.get("_plural", {})
note = notes.get("_note", {})
entries = {}


def add(key, source, line_no, lines, table):
    if key in skip or key in entries:
        return
    entry = {
        "en": plural.get(key, key),
        "where": f"{os.path.relpath(source, repo)}:{line_no}",
        "line": lines[line_no - 1].strip()[:160] if 0 < line_no <= len(lines) else "",
    }
    if table != "Localizable":
        entry["table"] = table
    if key in note:
        entry["note"] = note[key]
    entries[key] = entry


files = sorted(glob.glob(os.path.join(src_dir, "**", "*.stringsdata"), recursive=True))
if not files:
    sys.exit(f"no .stringsdata files under {src_dir}")
for f in files:
    d = json.load(open(f, encoding="utf-8"))
    source = d["source"]
    if os.path.basename(source) in skip_files:
        continue
    if not os.path.isfile(source):  # the widget's copy of the shortcuts metadata has no source file
        continue
    lines = open(source, encoding="utf-8").read().splitlines()
    for table, items in d.get("tables", {}).items():
        if table not in ("Localizable", "AppShortcuts"):
            continue
        for e in items:
            ln = e["location"]["startingLine"]
            if table == "AppShortcuts":
                for phrase in e.get("values", [e["key"]]):
                    add(phrase, source, ln, lines, table)
            else:
                add(e["key"], source, ln, lines, table)


def order(item):
    path, _, ln = item[1]["where"].rpartition(":")
    return (path, int(ln))


out = os.path.join(repo, "Localization", "en.json")
with open(out, "w", encoding="utf-8") as fh:
    json.dump(dict(sorted(entries.items(), key=order)), fh, ensure_ascii=False, indent=2)
    fh.write("\n")
print(f"wrote {out}: {len(entries)} keys")
