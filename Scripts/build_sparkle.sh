#!/bin/zsh
# Builds Sparkle, which updates Peel, from its source at a fixed commit: the framework Peel embeds, and the tools a
# release signs its update with. Every program Peel ships has an arm64e slice, which Sparkle's prebuilt framework lacks,
# and Sparkle's XPC services are left out, since Sparkle uses them only in a sandboxed app. The tools run only on the
# Mac that makes a release, so they are built without arm64e, in a folder of their own: they share Sparkle's static
# libraries with the framework, and built in one folder with other settings, each would replace the other's.
#
# Usage: zsh Scripts/build_sparkle.sh   (run once before building Peel, and again when the version below changes,
# after moving build/SparkleSource to the Trash)
set -euo pipefail
cd "$(dirname "$0")/.."

version=2.10.0
commit=eef1a539a373c1f1a320624b1130fc5de7b2e100
# No build folder's path may begin with the checkout's, even inside a name (build/Sparkle and build/SparkleBuild):
# the compiler then writes the modules it built relative to the source, cutting the path there, and dsymutil can't
# find them.
source=build/SparkleSource

if [ ! -d "$source" ]; then
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$version" \
        https://github.com/sparkle-project/Sparkle.git "$source"
fi
if [ "$(git -C "$source" rev-parse HEAD)" != "$commit" ] || [ -n "$(git -C "$source" status --porcelain)" ]; then
    echo "REFUSED: $source is not Sparkle $version as published ($commit). Move $source to the Trash, then run"
    echo "this again, which fetches it as published."
    exit 1
fi

build_scheme() {
    local scheme=$1 folder=$2
    shift 2
    if ! xcodebuild -project "$source/Sparkle.xcodeproj" -scheme "$scheme" -configuration Release \
        -destination 'generic/platform=macOS' -derivedDataPath "$folder" "$@" build > "$folder.log" 2>&1; then
        tail -20 "$folder.log"
        echo "REFUSED: Sparkle's $scheme did not build. The whole log is $folder.log."
        exit 1
    fi
}

build_scheme Sparkle build/SparkleBuild ENABLE_POINTER_AUTHENTICATION=YES \
    SPARKLE_EMBED_INSTALLER_LAUNCHER_XPC_SERVICE=0 SPARKLE_EMBED_DOWNLOADER_XPC_SERVICE=0
for tool in generate_keys sign_update generate_appcast; do
    build_scheme "$tool" build/SparkleTools
done
echo "Sparkle $version: the framework in build/SparkleBuild, its tools in build/SparkleTools"
