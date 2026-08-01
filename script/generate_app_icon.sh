#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT_DIR/assets/MicroLaunchpad.icns"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/micro-launchpad-icon.XXXXXX")"
ICONSET="$WORK_DIR/MicroLaunchpad.iconset"
SOURCE_PNG="$ICONSET/icon_512x512@2x.png"

trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$ICONSET"
swift "$ROOT_DIR/script/generate_app_icon.swift" "$SOURCE_PNG"

make_icon() {
  local pixels="$1"
  local name="$2"
  sips -z "$pixels" "$pixels" "$SOURCE_PNG" --out "$ICONSET/$name" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png

iconutil -c icns "$ICONSET" -o "$OUTPUT"
