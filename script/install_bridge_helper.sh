#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXECUTABLE="$ROOT_DIR/마이크로 런치패드.app/Contents/MacOS/ChatGPTMicroLaunchpad"
USER_HOME="$(/usr/bin/dscl . -read "/Users/$USER" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
LAUNCH_AGENTS_DIR="$USER_HOME/Library/LaunchAgents"
LABEL="com.pdg.chatgpt-micro-launchpad.bridge"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
TEMPLATE_PATH="$ROOT_DIR/script/$LABEL.plist"

if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "앱 번들을 먼저 빌드하세요: $ROOT_DIR/script/build_and_run.sh --package" >&2
  exit 1
fi

/bin/mkdir -p "$LAUNCH_AGENTS_DIR"
/usr/bin/sed "s|__APP_EXECUTABLE__|$APP_EXECUTABLE|g" "$TEMPLATE_PATH" > "$PLIST_PATH"
/bin/launchctl bootout "gui/$(/usr/bin/id -u)/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(/usr/bin/id -u)" "$PLIST_PATH"
/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/$LABEL"
echo "Background bridge installed: $PLIST_PATH"
