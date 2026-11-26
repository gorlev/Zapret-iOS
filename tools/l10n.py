#!/usr/bin/env python3
"""Checks the translations and writes them into the String Catalogs.

  tools/l10n.py status                 per language: keys done, missing, problems
  tools/l10n.py check [-m] [lang ...]  list missing / unknown keys and bad placeholders;
                                       exits 1 on any problem (-m: ignore missing keys)
  tools/l10n.py missing <lang>         the missing keys of one language, with where/line/note
  tools/l10n.py build                  write Shared/Localizable.xcstrings (app, widget and
                                       tunnel) and App/AppShortcuts.xcstrings (Siri phrases)

Localization/en.json is the brief (built by tools/l10n-extract.sh). Localization/<lang>.json
maps an English key to a string, or, for plural keys, to an object of CLDR categories.
A key a language does not have yet shows in English. Placeholders (%@, %lld, ${applicationName})
must match the English ones in kind and number; positional forms (%1$@, %2$lld) may reorder them.
"""
import json, os, re, sys
from collections import Counter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOC = os.path.join(REPO, "Localization")
LANGS = ["tr", "de", "es", "it", "fr", "pt-BR", "ru"]
PLURALS = {"ru": ["one", "few", "many", "other"]}
DEFAULT_PLURALS = ["one", "other"]
SPEC = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|d|lf|f)|\$\{(\w+)\}")
CATALOGS = {"Localizable": "Shared/Localizable.xcstrings", "AppShortcuts": "App/AppShortcuts.xcstrings"}


def specs(text):
    c = Counter()
    for m in SPEC.finditer(text):
        c["${" + m.group(3) + "}" if m.group(3) else "@" if m.group(2) == "@" else "lld" if m.group(2) in ("lld", "ld", "d") else "f"] += 1
    return c


def load(name):
    with open(os.path.join(LOC, f"{name}.json"), encoding="utf-8") as f:
        return json.load(f)


def brief():
    return load("en")


def english():
    return {k: v["en"] for k, v in brief().items()}


def check(lang, en, allow_missing=False):
    errors = []
    try:
        tr = load(lang)
    except FileNotFoundError:
        return [f"{lang}: Localization/{lang}.json is missing"]
    except json.JSONDecodeError as e:
        return [f"{lang}: not valid JSON: {e}"]
    missing, extra = set(en) - set(tr), set(tr) - set(en)
    if not allow_missing:
        errors += [f"{lang}: missing key {k!r}" for k in sorted(missing)]
    errors += [f"{lang}: unknown key {k!r}" for k in sorted(extra)]
    need = PLURALS.get(lang, DEFAULT_PLURALS)
    for key in sorted(set(en) & set(tr)):
        src, val = en[key], tr[key]
        if isinstance(src, dict):
            if not isinstance(val, dict):
                errors.append(f"{lang}: {key!r} must be a plural object with {need}")
                continue
            for cat in need:
                if not val.get(cat, "").strip():
                    errors.append(f"{lang}: {key!r} needs plural form {cat!r}")
            # A form may drop the number, but none may add a placeholder English
            # does not have, and %@ / ${...} must survive in every form.
            allowed = specs(src["other"])
            for cat, text in val.items():
                got = specs(text)
                if any(got[k] > allowed[k] for k in got) or any(got[k] != allowed[k] for k in allowed if k != "lld"):
                    errors.append(f"{lang}: {key!r} [{cat}] placeholders {dict(got)} vs English {dict(allowed)}")
        else:
            if not isinstance(val, str) or not val.strip():
                errors.append(f"{lang}: {key!r} is empty or not a string")
            elif specs(val) != specs(src):
                errors.append(f"{lang}: {key!r} placeholders {dict(specs(val))} vs English {dict(specs(src))}")
            else:
                # A value far longer or shorter than its English is usually a
                # value written under the wrong key. Catches a block shifted by one.
                ratio = len(val) / max(len(src), 1)
                if (ratio > 3 and len(val) > 30) or (ratio < 0.3 and len(src) > 30):
                    errors.append(f"{lang}: {key!r} looks like the value of another key: {val[:60]!r}")
    return errors


def catalog(table, en, langs):
    """One String Catalog: every key of this table, English plural forms, and each language's text."""
    info = brief()
    strings = {}
    for key, src in en.items():
        if info[key].get("table", "Localizable") != table:
            continue
        loc = {}
        if isinstance(src, dict):
            loc["en"] = plural_unit(src)
        for lang, tr in langs.items():
            if key in tr:
                loc[lang] = plural_unit(tr[key]) if isinstance(tr[key], dict) else unit(tr[key])
        entry = {"extractionState": "manual", "localizations": loc}
        if info[key].get("note"):
            entry["comment"] = info[key]["note"]
        strings[key] = entry
    return {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}


def unit(text):
    return {"stringUnit": {"state": "translated", "value": text}}


def plural_unit(forms):
    return {"variations": {"plural": {cat: unit(t) for cat, t in forms.items()}}}


def status(en):
    print(f"{len(en)} keys in en.json")
    for lang in LANGS:
        try:
            tr = load(lang)
        except (FileNotFoundError, json.JSONDecodeError):
            print(f"{lang:6} file missing or invalid")
            continue
        missing = len(set(en) - set(tr))
        problems = len(check(lang, en, allow_missing=True))
        print(f"{lang:6} {len(set(en) & set(tr)):4} done  {missing:4} missing  {problems} problems"
              + (f"   python3 tools/l10n.py missing {lang}" if missing else ""))


def main():
    args = sys.argv[1:]
    allow = "-m" in args
    args = [a for a in args if a != "-m"]
    if not args:
        print(__doc__)
        sys.exit(2)
    cmd, rest = args[0], args[1:]
    en = english()
    if cmd == "status":
        status(en)
    elif cmd == "check":
        langs = rest or LANGS
        errors = [e for lang in langs for e in check(lang, en, allow)]
        print("\n".join(errors) if errors else f"PASS l10n: {', '.join(langs)} match en.json ({len(en)} keys)")
        sys.exit(1 if errors else 0)
    elif cmd == "missing" and len(rest) == 1:
        try:
            tr = load(rest[0])
        except FileNotFoundError:
            tr = {}
        info = brief()
        out = {k: info[k] for k in en if k not in tr}
        print(json.dumps(out, ensure_ascii=False, indent=2))
    elif cmd == "build":
        present = {l: load(l) for l in LANGS if os.path.exists(os.path.join(LOC, f"{l}.json"))}
        errors = [e for lang in present for e in check(lang, en, allow_missing=True)]
        if errors:
            print("\n".join(errors))
            sys.exit(1)
        for table, path in CATALOGS.items():
            with open(os.path.join(REPO, path), "w", encoding="utf-8") as f:
                json.dump(catalog(table, en, present), f, ensure_ascii=False, indent=2, separators=(",", " : "))
                f.write("\n")
        print(f"wrote {', '.join(CATALOGS.values())} for en {' '.join(present)}")
    else:
        print(__doc__)
        sys.exit(2)


main()
