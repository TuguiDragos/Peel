## What this changes

<!-- One change per pull request. -->

## What goes wrong without it

## How you tested it

<!-- A test that failed before the change and passes after, and the page or command you checked it on. -->

## Checklist

- [ ] The app builds with no warnings, and `swift test --package-path Packages/PeelCore -Xswiftc -warnings-as-errors` passes, apart from `StringCatalogTests` for new or changed interface text, whose translations are added before merging.
- [ ] Nothing of the user's is deleted for good: every removal goes through `TrashService`.
- [ ] New or changed interface text is in English, and `python3 Scripts/sync_localizations.py` ran after a Debug build.
- [ ] A changed command of `peel` has its manual page written again with `python3 Scripts/generate_manual.py`.
- [ ] Nothing the change left unused stays behind.
- [ ] Every commit is signed off (`git commit -s`).
