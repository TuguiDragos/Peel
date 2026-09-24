#!/bin/zsh
# Builds, signs, notarizes, and checks a release of Peel, then prints the path and SHA-256 checksum of the final zip.
#
# Signing uses Xcode's `archive` and `exportArchive`, which do what notarization requires: they add a secure
# timestamp and remove the `com.apple.security.get-task-allow` entitlement. Nothing is sent to Apple's notary
# service until the app is archived, exported, and checked.
#
# Requires a Developer ID Application certificate in the keychain and a notary profile, stored once with
#   xcrun notarytool store-credentials Peel --apple-id <you> --team-id 6R6J264YA2
# which prompts for the app-specific password, so the password stays out of the shell history.
#
# Usage: zsh Scripts/release.sh [notary-profile]   (default profile: Peel)
set -euo pipefail
cd "$(dirname "$0")/.."

profile="${1:-Peel}"
build="build/Release"
archive="$build/Peel.xcarchive"
export_directory="$build/export"
app="$export_directory/Peel.app"

rm -rf "$build"
mkdir -p "$build"

echo "== Archiving"
# The output goes to a log, not through a pipe, so the `if` checks xcodebuild's own exit status.
if ! xcodebuild archive \
    -project Peel.xcodeproj \
    -scheme Peel \
    -configuration Release \
    -archivePath "$archive" \
    -derivedDataPath "$build/DerivedData" \
    > "$build/archive.log" 2>&1
then
    grep -E "error:" "$build/archive.log" || tail -20 "$build/archive.log"
    echo "REFUSED: the archive failed. The whole log is $build/archive.log"
    exit 1
fi
grep -E "warning:|ARCHIVE" "$build/archive.log" || true

echo "== Exporting with Developer ID"
cat > "$build/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>6R6J264YA2</string>
</dict>
</plist>
PLIST
if ! xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$build/ExportOptions.plist" \
    -exportPath "$export_directory" \
    > "$build/export.log" 2>&1
then
    grep -E "error:" "$build/export.log" || tail -20 "$build/export.log"
    echo "REFUSED: the export failed. The whole log is $build/export.log"
    exit 1
fi
grep -E "EXPORT" "$build/export.log" || true

echo "== What the four binaries are signed with"
for binary in \
    "$app" \
    "$app/Contents/MacOS/PeelHelper" \
    "$app/Contents/PlugIns/PeelFinder.appex" \
    "$app/Contents/Helpers/peel"
do
    echo "-- $binary"
    [ -e "$binary" ] || { echo "   REFUSED: $binary is not there"; exit 1; }
    codesign -d --verbose=2 "$binary" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp|flags" || true
    # Stop if `codesign` cannot read the binary, since its entitlements then cannot be checked.
    entitlements="$(codesign -d --entitlements - --xml "$binary" 2>/dev/null)" || { echo "   REFUSED: codesign cannot read $binary"; exit 1; }
    # Nothing that ships may be debuggable: `get-task-allow` lets any process of the same user take control of it.
    # Read whole before it is searched: with `pipefail`, a `grep -q` that stops at its match could end `plutil` with
    # SIGPIPE and turn the match into a pass. A binary with no entitlements prints nothing, which passes.
    printed="$(plutil -p - <<< "$entitlements" 2>/dev/null)" || true
    if [[ "$printed" == *get-task-allow* ]]; then
        echo "   REFUSED: $binary carries com.apple.security.get-task-allow"
        exit 1
    fi
done

echo "== Languages"
# Every language in the project's `knownRegions` (besides `en` and `Base`) must ship in the app and in the Finder
# extension. Without this check, a language missing from the build would quietly fall back to English.
languages=(${(f)"$(sed -n '/knownRegions = (/,/);/p' Peel.xcodeproj/project.pbxproj | tr -d ' \t,;"' | grep -vE '^(knownRegions=\(|\)|en|Base)$')"})
for language in $languages; do
    for bundle in "$app" "$app/Contents/PlugIns/PeelFinder.appex"; do
        [ -d "$bundle/Contents/Resources/$language.lproj" ] || { echo "REFUSED: $bundle has no $language.lproj"; exit 1; }
    done
done
echo "${#languages} languages besides English: $languages"

echo "== Notarizing"
zip="$build/Peel.zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"

echo "== Checks"
codesign --verify --deep --strict --verbose=2 "$app"
spctl -a -vvv -t exec "$app"
xcrun stapler validate "$app"
if command -v syspolicy_check > /dev/null; then
    syspolicy_check distribution "$app" || true
fi

echo "== Made"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
# Zip the app again after stapling, so the download carries its notarization ticket.
final="$build/Peel-$version.zip"
rm -f "$final"
ditto -c -k --keepParent "$app" "$final"
echo "Peel $version ($build_number)"
echo "$final"
shasum -a 256 "$final"
