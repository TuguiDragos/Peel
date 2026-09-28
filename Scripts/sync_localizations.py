"""Keeps the string catalogs in step with the strings in the code.

Run after building the Debug configuration into `build/DerivedData`:
    python3 Scripts/sync_localizations.py            writes the catalogs
    python3 Scripts/sync_localizations.py --check    writes nothing, says what would change, exits 1 if anything would

There are four catalogs in `Localization/`: Localizable for the app and for the Finder extension, AppShortcuts
(the phrases Siri and Spotlight match), and InfoPlist (the text macOS shows from the app's Info.plist, such as
its permission prompts). Apple's `xcstringstool sync` updates the first three from the build's `.stringsdata`
files. It adds new strings. A string that is not in the build output is removed when it has no translations,
and otherwise marked stale with its translations kept. The tool picks the strings table by the catalog's file
name, so each catalog is synced on a copy with the same name. InfoPlist has no `.stringsdata`: its English is
read from `Support/Peel-Info.plist`, and the app's name is marked as never translated.

The script stops instead of guessing. It exits when there is no build output, because a sync against nothing
would treat every string as gone. The app would still build and launch, so the damage could be committed
unnoticed. It also exits when a run would remove or mark stale more than a quarter of a catalog. Run with
`--force` to go ahead anyway.
"""
import argparse, glob, json, pathlib, plistlib, shutil, subprocess, sys, tempfile

PROJECT = pathlib.Path(__file__).resolve().parent.parent
INTERMEDIATES = PROJECT / "build/DerivedData/Build/Intermediates.noindex/Peel.build/Debug"
LOCALIZATION = PROJECT / "Localization"
SYNCED = [
    ("Peel", LOCALIZATION / "Peel/Localizable.xcstrings"),
    ("Peel", LOCALIZATION / "Peel/AppShortcuts.xcstrings"),
    ("PeelFinder", LOCALIZATION / "PeelFinder/Localizable.xcstrings"),
]
INFO_PLIST = PROJECT / "Support/Peel-Info.plist"
INFO_CATALOG = LOCALIZATION / "Peel/InfoPlist.xcstrings"
NAMES = ["CFBundleDisplayName", "CFBundleName"]
# Anything else is refused before a catalog is touched: a mistyped --check would otherwise write all four.
parser = argparse.ArgumentParser(
    description="Keeps the string catalogs in step with the strings in the code.", allow_abbrev=False
)
parser.add_argument(
    "--check", action="store_true", help="write nothing, say what would change, exit 1 if anything would"
)
parser.add_argument(
    "--force", action="store_true",
    help="go ahead even when a run would remove or mark stale over a quarter of a catalog",
)
options = parser.parse_args()
CHECK = options.check
FORCE = options.force


def empty_catalog():
    return {"sourceLanguage": "en", "strings": {}, "version": "1.0"}


# Removing or marking stale more than this share of a catalog suggests the build output is not from this code.
MOST_OF_IT = 0.25


def keys(catalog):
    return catalog.get("strings", {})


def stale(entry):
    return entry.get("extractionState") == "stale"


def write(path, catalog):
    text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
    path.write_text(text + "\n", encoding="utf-8")


def report(name, before, after):
    """Prints how two catalogs differ and returns True if they do. Exits if too many strings would go."""
    old, new = keys(before), keys(after)
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    went_stale = sorted(k for k in new if stale(new[k]) and k in old and not stale(old[k]))
    changed = added or removed or went_stale or json.dumps(before, sort_keys=True) != json.dumps(after, sort_keys=True)
    total = len(new)
    print(f"{name}: {total} strings, {len(added)} added, {len(removed)} removed, {len(went_stale)} marked stale")
    for key in added:
        print(f"  added: {key!r}")
    for key in removed:
        print(f"  removed: {key!r}")
    for key in went_stale:
        print(f"  stale: {key!r}")
    if old and len(removed) + len(went_stale) > MOST_OF_IT * len(old) and not FORCE:
        going = len(removed) + len(went_stale)
        sys.exit(f"{name}: {going} of {len(old)} strings would go. Check the build, then run with --force.")
    return bool(changed)


def synced(target, catalog_path):
    """Returns the catalog as `xcstringstool sync` would leave it, syncing a copy in a temporary folder."""
    files = glob.glob(str(INTERMEDIATES / f"{target}.build/Objects-normal/*/*.stringsdata"))
    if not files:
        sys.exit(f"no .stringsdata under {INTERMEDIATES / target}.build: build Debug into build/DerivedData first")
    with tempfile.TemporaryDirectory() as folder:
        copy = pathlib.Path(folder) / catalog_path.name
        if catalog_path.exists():
            shutil.copyfile(catalog_path, copy)
        else:
            write(copy, {"sourceLanguage": "en", "strings": {}, "version": "1.0"})
        subprocess.run(["xcrun", "xcstringstool", "sync", str(copy), "--stringsdata", *files], check=True)
        return json.loads(copy.read_text(encoding="utf-8"))


def info_plist(current):
    """Returns the InfoPlist catalog: the English from `INFO_PLIST`, with every existing translation kept. When the
    English changed, each translation still says the old text, so it is marked for review, which the catalog tests
    refuse until it is translated again."""
    plist = plistlib.loads(INFO_PLIST.read_bytes())
    strings = {}
    old = keys(current)
    # The keys whose text macOS shows: the permission prompts, and the copyright in Finder's Info window.
    shown = sorted(key for key in plist if key.endswith("UsageDescription") or key == "NSHumanReadableCopyright")
    for key in shown:
        entry = dict(old.get(key, {}))
        localizations = dict(entry.get("localizations", {}))
        english = localizations.get("en", {}).get("stringUnit", {}).get("value")
        if english is not None and english != plist[key]:
            print(f"  changed in English, translations to review: {key}")
            localizations = {
                language: {"stringUnit": {**value["stringUnit"], "state": "needs_review"}}
                if "stringUnit" in value else value
                for language, value in localizations.items()
            }
        localizations["en"] = {"stringUnit": {"state": "new", "value": plist[key]}}
        entry["localizations"] = localizations
        entry["extractionState"] = "extracted_with_value"
        entry.pop("shouldTranslate", None)
        strings[key] = entry
    for key in NAMES:
        entry = {k: v for k, v in old.get(key, {}).items() if k == "comment"}
        entry["shouldTranslate"] = False
        strings[key] = entry
    return {"sourceLanguage": "en", "strings": strings, "version": current.get("version", "1.0")}


differs = False
for target, path in SYNCED:
    before = json.loads(path.read_text(encoding="utf-8")) if path.exists() else empty_catalog()
    after = synced(target, path)
    name = f"{target} {path.stem}"
    if report(name, before, after):
        differs = True
        if not CHECK:
            write(path, after)

before = json.loads(INFO_CATALOG.read_text(encoding="utf-8")) if INFO_CATALOG.exists() else empty_catalog()
after = info_plist(before)
if report("Peel InfoPlist", before, after):
    differs = True
    if not CHECK:
        write(INFO_CATALOG, after)

if CHECK and differs:
    sys.exit("the catalogs are not in step with the code: run python3 Scripts/sync_localizations.py")
