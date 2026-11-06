#!/bin/zsh
# Makes Peel's disk image: the app, a link to Applications, and a window that shows where to drag the app.
# dmgbuild writes the window's layout without opening Finder, installed by uv into an environment of its own from
# dmgbuild-requirements.txt, which pins each package by the hash of its files.
#
# Usage: zsh Scripts/make_dmg.sh <Peel.app> <image.dmg>
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -eq 2 ] || { echo "usage: zsh Scripts/make_dmg.sh <Peel.app> <image.dmg>"; exit 64; }
app="$1"
image="$2"
command -v uv > /dev/null || { echo "REFUSED: uv is not installed. Install it with: brew install uv"; exit 1; }

# The window, and each icon's center in points from its top left corner. The background is drawn for these.
width=640
height=400
peel_x=170
applications_x=470
icons_y=190

background="$(dirname "$image")/disk-image-background"
mkdir -p "$background"
swift Scripts/dmg_background.swift "$background" $width $height $peel_x $applications_x $icons_y
environment="$(dirname "$image")/dmgbuild-environment"
uv venv --quiet --clear "$environment"
uv pip install --quiet --python "$environment/bin/python" --require-hashes \
    --requirement Scripts/dmgbuild-requirements.txt
"$environment/bin/dmgbuild" -s Scripts/dmg_settings.py \
    -D app="$app" -D background="$background/background.png" \
    -D width=$width -D height=$height -D peel_x=$peel_x -D applications_x=$applications_x -D icons_y=$icons_y \
    Peel "$image"
