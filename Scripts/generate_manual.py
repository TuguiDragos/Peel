"""Keeps the manual page of the `peel` tool, `Support/peel.1`, in step with the tool.

Run after building the Debug configuration into `build/DerivedData`:
    python3 Scripts/generate_manual.py            writes the page when the tool says something new
    python3 Scripts/generate_manual.py --check    writes nothing, and exits 1 when the page is behind

The page is written by `generate-manual`, the tool swift-argument-parser ships for its GenerateManual plugin, from
what the built `peel` says about itself. The tool is built from the copy of swift-argument-parser the Debug build
resolved, into `build/Tools`, so nothing is downloaded. The date on the page is the day its text last changed:
a page whose text is the same keeps the date it has. The app build copies the page into Peel.app, and Homebrew
installs it from there.
"""
import pathlib, subprocess, sys, tempfile

PROJECT = pathlib.Path(__file__).resolve().parent.parent
DERIVED = PROJECT / "build/DerivedData"
ARGUMENT_PARSER = DERIVED / "SourcePackages/checkouts/swift-argument-parser"
TOOL = DERIVED / "Build/Products/Debug/Peel.app/Contents/Helpers/peel"
SCRATCH = PROJECT / "build/Tools/argument-parser"
PAGE = PROJECT / "Support/peel.1"
CHECK = "--check" in sys.argv[1:]


def without_date(page):
    """The page without its `.Dd` line, which says only when it was written."""
    return [line for line in page.splitlines() if not line.startswith(".Dd ")]


def main():
    if not TOOL.exists() or not ARGUMENT_PARSER.exists():
        sys.exit("Build Peel's Debug configuration into build/DerivedData first.")
    subprocess.run(
        ["swift", "build", "--package-path", ARGUMENT_PARSER, "--scratch-path", SCRATCH,
         "-c", "release", "--target", "generate-manual"],
        check=True, stdout=subprocess.DEVNULL,
    )
    with tempfile.TemporaryDirectory() as folder:
        subprocess.run(
            [SCRATCH / "release/generate-manual", TOOL, "--output-directory", folder],
            check=True, stdout=subprocess.DEVNULL,
        )
        new = (pathlib.Path(folder) / "peel.1").read_text(encoding="utf-8")
    old = PAGE.read_text(encoding="utf-8") if PAGE.exists() else ""
    if without_date(new) == without_date(old):
        print("Support/peel.1 is in step with the tool.")
        return
    if CHECK:
        sys.exit("Support/peel.1 is behind the tool. Run python3 Scripts/generate_manual.py after a Debug build.")
    PAGE.write_text(new, encoding="utf-8")
    print("Wrote Support/peel.1.")


main()
