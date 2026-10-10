#!/bin/zsh
# Builds Sparkle, which updates Peel, from its source at a fixed commit: the framework Peel embeds, and the tools a
# release signs its update with. Every program Peel ships has an arm64e slice, which Sparkle's prebuilt framework lacks,
# and Sparkle's XPC services are left out, since Sparkle uses them only in a sandboxed app.
#
# Usage: zsh Scripts/build_sparkle.sh   (run once before building Peel, and again when the version below changes)
set -euo pipefail
cd "$(dirname "$0")/.."

version=2.10.0
commit=eef1a539a373c1f1a320624b1130fc5de7b2e100
source=build/Sparkle

if [ ! -d "$source" ]; then
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$version" \
        https://github.com/sparkle-project/Sparkle.git "$source"
fi
if [ "$(git -C "$source" rev-parse HEAD)" != "$commit" ] || [ -n "$(git -C "$source" status --porcelain)" ]; then
    echo "REFUSED: $source is not Sparkle $version as published ($commit)."
    exit 1
fi

for scheme in Sparkle generate_keys sign_update generate_appcast; do
    if ! xcodebuild -project "$source/Sparkle.xcodeproj" -scheme "$scheme" -configuration Release \
        -derivedDataPath build/SparkleBuild ENABLE_POINTER_AUTHENTICATION=YES \
        SPARKLE_EMBED_INSTALLER_LAUNCHER_XPC_SERVICE=0 SPARKLE_EMBED_DOWNLOADER_XPC_SERVICE=0 \
        build > build/SparkleBuild.log 2>&1; then
        tail -20 build/SparkleBuild.log
        echo "REFUSED: Sparkle's $scheme did not build. The whole log is build/SparkleBuild.log."
        exit 1
    fi
done
echo "Sparkle $version: build/SparkleBuild/Build/Products/Release"
