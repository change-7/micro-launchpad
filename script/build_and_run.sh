#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ChatGPTMicroLaunchpad"
BUNDLE_ID="com.pdg.chatgpt-micro-launchpad.native"
APP_DISPLAY_NAME="마이크로 런치패드"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_DISPLAY_NAME.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_RESOURCES="$APP_BUNDLE/Contents/Resources"

if [[ "$MODE" != "--package" && "$MODE" != "package" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi
swift build
bash "$ROOT_DIR/script/generate_app_icon.sh"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$(swift build --show-bin-path)/$APP_NAME" "$APP_MACOS/$APP_NAME"
cp "$ROOT_DIR/script/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/script/PkgInfo" "$APP_BUNDLE/Contents/PkgInfo"
cp "$ROOT_DIR/assets/MicroLaunchpad.icns" "$APP_RESOURCES/MicroLaunchpad.icns"
chmod +x "$APP_MACOS/$APP_NAME"
codesign --force --deep --sign - -r "=designated => identifier \"$BUNDLE_ID\"" "$APP_BUNDLE"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE"

case "$MODE" in
  run) /usr/bin/open "$APP_BUNDLE" ;;
  --package|package) ;;
  --verify|verify) /usr/bin/open "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "usage: $0 [run|--verify]" >&2; exit 2 ;;
esac
