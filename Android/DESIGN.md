# Galaxy Micro Launchpad Android UI

## Visual contract

The controller is a landscape-first, flat black utility surface. It uses thin gray rules, white typography, and a restrained status palette; no gradients, decorative shadows, or rounded card stacks.

## Tokens

- Surface: `Black #050505`; secondary surface `Tile #191919`; track `GaugeTrack #303030`.
- Text: `TextPrimary #F2F2F2`; muted text `TextMuted #9A9A9A`.
- Status: `Green #32E875`; error/low usage `GaugeLow #FF3B30`; mid usage `GaugeMid #FFB020`; healthy usage `GaugeCool #22C7A8`; full usage `GaugeHigh #3B82F6`.
- Layout: 20dp horizontal page inset, 58dp header, compact 38dp bottom navigation, 3dp utility radius. The shared header's running indicator is an 18dp inline primitive so it fits the 32dp header without changing its height. The optional idle-blackout overlay activates after 2 minutes without touch and does not participate in layout. The Buttons grid derives tile height from the available landscape viewport and uses a 36dp icon, 4dp icon/label gap, and 14sp medium label so the tile's vertical surface is used clearly without clipping. Codex content uses a balanced 18dp top inset and 24dp bottom breathing room, with the status block, gauges, and health row distributed across the full available height.
- Type: 28sp page title, 18sp connection label, 13sp metadata, 12sp usage labels, 32sp usage values, 14sp medium reset times.

## Reusable primitives

- `Header`: connection state, live message, and current page label.
- `RunningStatusIndicator`: an 18dp rotating sweep and pulsing core mounted in the shared header while Codex is running, keeping work activity visible on both Buttons and Codex pages.
- `IdleBlackoutOverlay`: an opt-in full-screen black touch surface shown after 2 minutes of inactivity. A tiny green corner dot distinguishes the active overlay from a powered-off display. A touch dismisses it, while Codex, bridge, command, or usage events dismiss it automatically.
- `ControlGrid`: a 4-column, 4-row command grid whose tile height derives from the available landscape viewport so the Buttons page uses the full vertical surface.
- `ButtonPageSelector`: the former category rail is replaced by explicit `PAGE 01`–`PAGE 03` selectors. Vertical swipes change pages with a directional slide/fade transition and wrap from the last page to the first (and back).
- `ControlGrid` transport: each tile sends a stable command ID through the newline-delimited Bonjour/TCP bridge and displays the Mac helper's acknowledgement in the shared header.
- `SmartphoneIconAsset`: titled app actions carry a compact 96px PNG exported from the selected macOS app. Android decodes and caches the asset per button, while SF Symbol mapping remains the fallback for non-app actions or older bridge payloads. Empty Mac button slots keep their grid position and tile border/background, but render without icon or label and do not dispatch commands.
- `UsageGauge`: a labeled remaining-usage value and linear gauge. The left usage summary places each Korean-localized next-reset time directly beneath its large percentage in a readable medium 14sp treatment: `HH:mm` for 5-hour and `M월 d일 HH:mm` for 1-week, with no extra prefix or timezone suffix. Solid gauge color uses clear bands: red (0–20%), amber (21–50%), teal (51–75%), and blue (76–100%).
- `StatusLine`: compact health indicator for bridge, app server, and activity.
- `CompletionReveal`: a transition guard that reacts only when Codex enters `completed`, selects the Codex page from any other page, and requests a brief screen wake so the completion motion is visible. The same reveal path is used by the scheduled 5-hour reset alarm.
- `ApprovalPrompt`: a Codex approval card shown when the Mac app server has a pending command, file-change, permission, or confirmation request. It exposes explicit `승인` and `거절` actions and keeps the request detail visible before sending the response back to the Mac bridge.
- `BridgeConnectionSettingsDialog`: a compact selector opened from the header settings icon. It offers a 10-minute-step post-screen-off grace period (10분–12시간) or 계속 유지, plus an optional daily 절전 시간대 (start/end) in which screen-off pauses immediately and screen-on resumes the bridge.

## Accessibility and motion

- Preserve high-contrast white/gray text on black surfaces.
- Status motion is limited to the Codex activity indicators; usage gauges remain stable and communicate state through value, label, and color together.
- Codex activity motion: `RUNNING` uses a repeating progress sweep and pulse, `WAITING FOR APPROVAL` uses a slow breathing ring, `COMPLETED` uses a one-shot check draw-in with a brief halo, `FAILED` uses a short warning shake/pulse, and `IDLE` remains still.
- Running visibility: while the normalized remote activity is `running`, `RunningStatusIndicator` continuously rotates and pulses in the always-mounted header; it is removed immediately for every non-running state. A running-state reveal never forces the user away from Buttons; only completion, approval, or an explicit Codex reveal changes the selected tab.
- Idle blackout: when enabled in settings, the app keeps the display awake while foregrounded, shows the black overlay after the inactivity timeout, and reveals the underlying page on touch or a remote event without changing the page layout.
- Completion routing: when a new `completed` event arrives while Buttons is visible, the app reveals Codex and lets the one-shot check/halo animation play from its beginning. If the display is off, the activity requests a short wake window before presenting the Codex page.
- Approval routing: when a new approval/confirmation request arrives while Buttons is visible, the app reveals Codex, wakes the display when needed, and shows a breathing approval motion with `승인` and `거절` actions. The selected decision is returned to the originating App Server request.
- Primary page navigation: the app has two pages, Buttons and Codex. A horizontal swipe can start anywhere in the full app surface, commits after a short 32dp movement, and advances to the next page with a 150ms directional slide/100ms fade. Repeated swipes in one direction wrap continuously; the bottom navigation mirrors the same two-page selection.
- Reset wake: the 5-hour `resetsAt` timestamp is sent as Unix epoch seconds and scheduled as an `RTC_WAKEUP` alarm with a direct `MainActivity` PendingIntent. The activity receives the Codex reveal intent, allowing the screen to wake at the reset boundary without depending on a foreground app page.
- Screen-off connection policy: the foreground bridge service keeps the socket and discovery locks only for the selected 10-minute-step grace period, then pauses the client while retaining the service. During the optional daily 절전 시간대, screen-off pauses immediately; a screen-on event resumes discovery immediately. The low-priority ongoing service notification explains whether the bridge is active or paused.
