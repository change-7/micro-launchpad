# Android UI visual QA

## Final result: passed for the requested layout change

- Build evidence: `./gradlew :app:assembleDebug` completed successfully on 2026-08-27.
- Device evidence: latest debug APK installed on the connected Samsung SM-G986N (2400×1080 landscape).
- Covered pages: Buttons and Codex.
- Fresh captures: `design/qa/buttons-swipe-proof.png`, `design/qa/codex-static-proof.png`, and `design/qa/buttons-return-proof.png`.
- Page navigation result: Trackpad is removed; the two remaining pages switch with horizontal swipes and a directional slide/fade transition. Bottom navigation contains only Buttons and Codex.
- Codex result: settled recapture includes the shared `Mac connected / Codex working` header.
- Scope note: the current prototype wires drag-to-move-cursor interaction only; Mac HID/event transport and additional gestures remain follow-up implementation work.

## Codex bridge verification

- Mac publishes a newline-delimited state over Bonjour-discovered TCP (`_micro-launchpad._tcp`, port `43123`).
- Android discovers the Mac service, sends a protocol hello, and renders the received connection/activity/usage state.
- Final physical-device evidence: `Mac connected`, `Codex 작업 완료`, `Mac bridge`, `Codex App Server`, `Activity: COMPLETED`, `5-hour 62%`, `1-week 77%`.
- Fresh capture: `Android/design/qa/codex-status-final.png` (2400×1080 RGBA PNG), taken from the connected Galaxy after the final APK install.
- The 5-hour and 1-week values are live complements of the Mac's respective `usedPercent` windows (38% and 23% in this capture). The progress bar is explicitly labeled as the 1-week window.
- Pause/Stop controls are removed from this page; its content is limited to live status, motion indicator, and remaining-usage telemetry.
- Usage gauge update: the Codex page now renders both `5-hour remaining` and `1-week remaining` linear gauges. Each gauge uses a solid remaining-capacity band (red 0–20%, amber 21–50%, teal 51–75%, blue 76–100%) and the large percentage value uses the same color.
- Fresh capture: `Android/design/qa/codex-usage-gauges.png` (2400×1080 landscape) shows live `5-hour 58%` in teal and `1-week 77%` in blue.
- Usage freshness: the Mac helper now re-reads `account/rateLimits/read` every 30 seconds while connected, so both gauges update without restarting the UI or Android app. Production helper verification showed the live values change to `5-hour 49%` and `1-week 75%` after reconnecting.
- Fresh capture: `Android/design/qa/codex-usage-refresh-fixed.png` (2400×1080 landscape).
- Reset-time display: the large left-side `5-hour` and `1-week` percentages now show their independent next reset in Korean local time (`Asia/Seoul`) directly beneath each value. The 5-hour entry is time-only (`HH:mm`); the 1-week entry includes date and time (`M월 d일 HH:mm`). Neither entry adds a prefix or `KST` suffix; missing timestamps fall back to `—`.
- Fresh capture: `Android/design/qa/codex-reset-times-left-large.png` (2400×1080 landscape) shows both reset times directly beneath their corresponding percentages with the increased readable type.
- Completion reveal: `RemoteBridgeClient` emits a monotonic completion event only when the activity enters `completed`; the app responds by selecting the Codex page when Buttons is active. The activity also requests `FLAG_SHOW_WHEN_LOCKED`/`FLAG_TURN_SCREEN_ON` and a short `WakeLock` window when the display is non-interactive.
- Fresh capture: `Android/design/qa/codex-completion-autonavigate.png` (2400×1080 landscape) shows the app launching from the default Buttons state and automatically settling on the Codex page with the `COMPLETED` check motion state.
- Working-state fix: the Mac bridge clears a stale desktop `COMPLETED` override as soon as a new App Server turn enters `running`/approval, and Android normalizes equivalent `working`/`in_progress` payloads to `RUNNING`.
- Fresh capture: `Android/design/qa/codex-reset-final-v3.png` (Codex page) shows live `Codex 작업 중`, `RUNNING`, the green progress motion, both usage gauges/reset times, and the complete shared chrome.
- Progress-state restore: all streamed `turn/*`, `item/*`, realtime, and raw-response events keep the Mac state in `RUNNING`; Android reveals the Codex page when the first state after an app restart is still running.
- Fresh Galaxy restart capture: `Android/design/qa/codex-restart-fixed-settled.png` shows the restored Codex page, `2개 작업 중`, and the live `RUNNING` motion without exposing the internal session-count variable name.
- Swipe responsiveness: horizontal page changes commit as soon as the 32dp drag threshold is crossed from anywhere on the app surface, with the page transition shortened to 150ms/100ms slide-fade timing. Repeated swipes in one direction continue wrapping between the two tabs. Fresh Galaxy captures `Android/design/qa/swipe-anywhere-buttons-start.png`, `Android/design/qa/swipe-anywhere-header-codex.png`, `Android/design/qa/swipe-anywhere-content-buttons.png`, and `Android/design/qa/swipe-anywhere-bottom-codex.png` cover recognition from header, content, and bottom regions; the live completion reveal may keep Codex selected while that state is active.
- Approval attention: the Mac bridge now forwards pending command/file-change/permission approval requests as a Codex state payload. Android reveals the Codex page, wakes the display when needed, shows the breathing approval motion, and renders `승인`/`거절` actions that return the selected JSON-RPC decision to the waiting App Server request.
- Approval smoke evidence: `Android/design/qa/codex-approval-path-smoke.png` is a fresh Galaxy capture from the updated APK; the normal Codex/Buttons surface remains intact when no approval is pending.
- Five-hour reset wake: `CodexResetScheduler` schedules the received Unix-epoch 5-hour reset timestamp with `RTC_WAKEUP` and a direct `MainActivity` PendingIntent. The activity receives a Codex reveal intent so screen wake and page navigation share the completion-event path even when the app is asleep or on another page.
- Multi-session completion: the Mac bridge increments a monotonic per-session completion event whenever any monitored Codex transcript completes. Android reveals Codex and plays the one-shot completion check/halo even when the aggregate activity remains `RUNNING` for another active session.
- Fresh smoke capture: `Android/design/qa/codex-multi-session-final.png` was taken from the final APK on the connected Galaxy after installation.

## Background bridge verification

- `script/install_bridge_helper.sh` installs `com.pdg.chatgpt-micro-launchpad.bridge` as a per-user LaunchAgent.
- The helper launches the production executable with `--bridge-only`, keeps the Bonjour/TCP bridge and Codex monitor alive, and suppresses the main UI window.
- `launchctl print gui/501/com.pdg.chatgpt-micro-launchpad.bridge` reported `state = running` while the main UI was not launched; the Galaxy still rendered live `Mac connected`, `Codex connected`, `RUNNING`, `5-hour 58%`, and `1-week 77%` in `Android/design/qa/codex-helper-only.png`.
- This capture was taken after stopping the regular UI process and leaving only the `--bridge-only` LaunchAgent process running, so the connection does not depend on the visible Mac app window.

## Buttons bridge verification

- The Buttons page now sends each tile's command ID over the same Bonjour/TCP bridge and renders the Mac helper's `commandResult` message in the header.
- The Mac helper maps the default set to native app launches, browser/settings URLs, and keyboard shortcuts: Terminal, Browser, Files, Search, Capture, Clipboard, Music, Volume, Focus, Settings, Run, Pause, and Stop.
- The Galaxy physical tap on Terminal returned `앱을 열었습니다.` while the Mac helper was running headlessly via LaunchAgent.
- Fresh capture: `Android/design/qa/buttons-terminal-command-result.png` (2400×1080 landscape).
- Command acknowledgements are color-coded in the header: green for success and red for a failed/unsupported Mac action.
- The 16-button layout is a 4×4 grid with equal-height tiles and a compact 38dp bottom navigation row; the final row is fully visible above the navigation.
- Fresh capture: `Android/design/qa/buttons-full-grid.png` (2400×1080 landscape).
- Smartphone button icons now map the Mac app's SF Symbol identifiers to the closest bundled Android Material icons across execution, device, file, communication, media, network, system, and developer categories; unsupported future identifiers retain the overflow fallback instead of breaking the grid.
- Fresh icon propagation capture: `Android/design/qa/icon-mapping-buttons-final.png` (2400×1080 landscape) from the connected Galaxy after installing the updated APK.
- App icon sync: the Mac bridge exports selected macOS app icons as compact PNG assets keyed by smartphone button ID. Android renders the received asset for app actions and falls back to the mapped SF Symbol when an asset is unavailable.
- Fresh app-icon capture: `Android/design/qa/icon-sync-buttons-final-v3.png` (2400×1080 landscape) from the connected Galaxy after rebuilding both sides; Codex, Terminal, Whale, Finder, Music, and System Settings show their macOS app icons on the phone.
- Fresh button-scale capture: `Android/design/qa/buttons-balanced-content-final.png` (2400×1080 landscape) from the connected Galaxy; the 4×4 tiles use larger 36dp icons and 14sp labels while keeping every label inside its tile and clear of the bottom navigation.
- Fresh Codex regression capture: `Android/design/qa/codex-balanced-content-final.png` (2400×1080 landscape) confirms the adjacent Codex page remains intact after the Buttons tile sizing update.
- Empty-slot handling: Android keeps the grid position, tile border, and tile background for remote buttons whose Mac title is blank, but renders no icon or label and does not dispatch a command; no unused app-icon asset is decoded.
- Fresh empty-slot capture: `Android/design/qa/buttons-empty-slot-bordered-final.png` (2400×1080 landscape) confirms the blank Mac slot remains a bordered empty third position in the first row while the configured buttons keep their original order and spacing.
- Running-state reconnect QA: `Android/design/qa/codex-running-reconnect-final.png` (2400×1080 landscape) shows the Android app restored into `RUNNING` with `Codex 작업 중` after a restart while the Mac bridge still reported active work.
- Asset transport efficiency: icon payloads are now sent as a separate `smartphoneIconAssets` message only on connection or asset change; recurring state updates no longer resend base64 image data.
- Bridge wire smoke: a fresh local hello returned `state` with `inlineAssets=false`, followed by one `smartphoneIconAssets` envelope containing 17 app assets.
- Page rail verification: the former `DEV`, `Codex working`, `Profile`, `Dev`, `Work`, and `Media` labels are removed. The left rail now selects `PAGE 01`–`PAGE 03`; tapping `PAGE 02` changes the 4×4 button set.
- Stable PAGE 02 capture: `Android/design/qa/buttons-page02-settled-v2.png` was taken from the latest APK after waiting 2 seconds for the slide/fade transition to finish; it includes the persistent header, page rail, all 16 tiles, and bottom navigation.
- Swipe verification: an upward swipe from `PAGE 02` advances to `PAGE 03`; the transition uses a 260ms directional slide with a short fade. `PAGE 03` upward wraps to `PAGE 01`, and `PAGE 01` downward wraps to `PAGE 03`.
- Main page swipe verification: a left/right swipe switches between Buttons and Codex, with wrap-around in either direction and no Trackpad destination.
- Fresh wrap capture: `Android/design/qa/buttons-page-wrap.png` (2400×1080 landscape) shows the wrapped `PAGE 01` selection after the physical Galaxy swipe.
- Reverse wrap capture: `Android/design/qa/buttons-page-wrap-reverse.png` shows the complementary downward wrap from `PAGE 01` to `PAGE 03`.
