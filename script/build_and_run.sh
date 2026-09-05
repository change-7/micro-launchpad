#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ChatGPTMicroLaunchpad"
PRODUCTION_BUNDLE_ID="com.pdg.chatgpt-micro-launchpad"
DEVELOPMENT_BUNDLE_ID="com.pdg.chatgpt-micro-launchpad.development"
APP_DISPLAY_NAME="마이크로 런치패드"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_DISPLAY_NAME.app"
DEVELOPMENT_APP_BUNDLE="$ROOT_DIR/.build/$APP_DISPLAY_NAME 개발.app"
BUILD_VERSION="${BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}"

stop_development_app() {
  local development_pids
  development_pids="$(pgrep -f "/\\.build/.*/Contents/MacOS/$APP_NAME$" || true)"
  [[ -z "$development_pids" ]] || kill $development_pids
}

assemble_bundle() {
  local bundle_path="$1"
  local bundle_id="$2"
  local display_name="$3"
  local staging_path="$ROOT_DIR/.build/.bundle-staging-${bundle_id//./-}"
  local macos_path="$staging_path/Contents/MacOS"
  local resources_path="$staging_path/Contents/Resources"
  local resource_bundle_path="$(swift build --show-bin-path)/${APP_NAME}_${APP_NAME}.bundle"

  rm -rf "$staging_path"
  mkdir -p "$macos_path"
  mkdir -p "$resources_path"
  cp "$(swift build --show-bin-path)/$APP_NAME" "$macos_path/$APP_NAME"
  cp "$ROOT_DIR/script/Info.plist" "$staging_path/Contents/Info.plist"
  cp "$ROOT_DIR/script/PkgInfo" "$staging_path/Contents/PkgInfo"
  cp "$ROOT_DIR/assets/MicroLaunchpad.icns" "$resources_path/MicroLaunchpad.icns"
  if [[ ! -d "$resource_bundle_path" ]]; then
    echo "SwiftPM resource bundle not found: $resource_bundle_path" >&2
    exit 1
  fi
  cp -R "$resource_bundle_path" "$resources_path/"
  plutil -replace CFBundleIdentifier -string "$bundle_id" "$staging_path/Contents/Info.plist"
  plutil -replace CFBundleName -string "$display_name" "$staging_path/Contents/Info.plist"
  plutil -replace CFBundleDisplayName -string "$display_name" "$staging_path/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$BUILD_VERSION" "$staging_path/Contents/Info.plist"
  chmod +x "$macos_path/$APP_NAME"
  xattr -cr "$staging_path"
  codesign --force --deep --sign - -r "=designated => identifier \"$bundle_id\"" "$staging_path"
  rm -rf "$bundle_path"
  mv "$staging_path" "$bundle_path"
}

if [[ "$MODE" != "--package" && "$MODE" != "package" ]]; then
  stop_development_app
fi
swift build
bash "$ROOT_DIR/script/generate_app_icon.sh"
assemble_bundle "$APP_BUNDLE" "$PRODUCTION_BUNDLE_ID" "$APP_DISPLAY_NAME"

case "$MODE" in
  run)
    assemble_bundle "$DEVELOPMENT_APP_BUNDLE" "$DEVELOPMENT_BUNDLE_ID" "$APP_DISPLAY_NAME 개발"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEVELOPMENT_APP_BUNDLE"
    /usr/bin/open -n -a "$DEVELOPMENT_APP_BUNDLE"
    ;;
  --package|package) ;;
  --verify|verify)
    assemble_bundle "$DEVELOPMENT_APP_BUNDLE" "$DEVELOPMENT_BUNDLE_ID" "$APP_DISPLAY_NAME 개발"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEVELOPMENT_APP_BUNDLE"
    /usr/bin/open -n -a "$DEVELOPMENT_APP_BUNDLE"
    sleep 1
    pgrep -f "/\\.build/.*/Contents/MacOS/$APP_NAME$" >/dev/null
    ;;
  *) echo "usage: $0 [run|--verify]" >&2; exit 2 ;;
esac
