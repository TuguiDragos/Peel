#!/bin/zsh
# Renders `Peel.icon` as `Peel.png` (light, 320 by 320 pixels) and `Peel-Dark.png` (dark, 1024 by 1024 pixels,
# the icon's full size). The README shows `Peel-Dark.png`.
set -euo pipefail
cd "${0:A:h}"
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
"$ictool" Peel.icon --export-image --output-file Peel.png \
  --platform macOS --rendition Default --width 320 --height 320 --scale 1
"$ictool" Peel.icon --export-image --output-file Peel-Dark.png \
  --platform macOS --rendition Dark --width 1024 --height 1024 --scale 1
