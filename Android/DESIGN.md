# Galaxy Micro Launchpad Android UI

## Visual contract

The controller is a landscape-first, flat black utility surface. It uses thin gray rules, white typography, and a restrained status palette; no gradients, decorative shadows, or rounded card stacks.

## Tokens

- Surface: `Black #050505`; secondary surface `Tile #191919`; track `GaugeTrack #303030`.
- Text: `TextPrimary #F2F2F2`; muted text `TextMuted #9A9A9A`.
- Status: `Green #32E875`; error/low usage `GaugeLow #FF3B30`; mid usage `GaugeMid #FFB020`; healthy usage `GaugeCool #22C7A8`; full usage `GaugeHigh #3B82F6`.
- Layout: 20dp horizontal page inset, 58dp header, no bottom navigation bar, 3dp utility radius. The shared header's running indicator is an 18dp inline primitive so it fits the 32dp header without changing its height. The optional idle-blackout overlay activates after 2 minutes without touch and does not participate in layout. The Buttons grid derives tile height from the available landscape viewport and uses a 42dp icon, 4dp icon/label gap, and 14sp medium label so button icons read clearly while the tile's vertical surface remains unclipped. Codex content uses a balanced 18dp top inset and 24dp bottom breathing room; the left usage summary is weighted toward the upper-middle of the viewport, while the status block, gauges, and health row use the remaining height.
- Type: 28sp page title, 18sp connection label, 15sp usage heading, 13sp usage labels, 36sp usage values, 16sp medium reset times, and 14sp countdowns.

## Reusable primitives

- `Header`: connection state, independent Codex working/completion statuses, live message, and current page label. The working status is visible whenever `activeSessionCount > 0`; the completion status is an independent blink acknowledgement, so one completed session can flash beside the still-running status of another session.
- `RunningStatusIndicator`: an 18dp rotating sweep and pulsing core mounted in the shared header whenever `activeSessionCount > 0`, keeping work activity visible on both Buttons and Codex pages.
- `CompletionStatusFlash`: a short green alpha blink on the independent shared-header completion status when a new Codex completion event arrives. It is a status acknowledgement only and does not change the selected page.
- `IdleBlackoutOverlay`: an opt-in full-screen black touch surface shown after 2 minutes of inactivity. A tiny green corner dot distinguishes the active overlay from a powered-off display. A touch dismisses it, while Codex, bridge, command, or usage events dismiss it automatically.
- `ControlGrid`: a 4-column, 4-row command grid whose tile height derives from the available landscape viewport so the Buttons page uses the full vertical surface.
- `ButtonPageSelector`: the former category rail is replaced by explicit `PAGE 01`–`PAGE 03` selectors. Vertical swipes change pages with a directional slide/fade transition and wrap from the last page to the first (and back).
- `ControlGrid` transport: each tile sends a stable command ID through the newline-delimited Bonjour/TCP bridge and displays the Mac helper's acknowledgement in the shared header.
- `SmartphoneIconAsset`: titled app actions carry a compact 96px PNG exported from the selected macOS app. Android decodes and caches the asset per button, while SF Symbol mapping remains the fallback for non-app actions or older bridge payloads. Empty Mac button slots keep their grid position and tile border/background, but render without icon or label and do not dispatch commands.
- `UsageGauge`: a labeled remaining-usage value and linear gauge. The left usage summary places each Korean-localized next-reset time directly beneath its large percentage in a readable medium 16sp treatment: `HH:mm` for 5-hour and `M월 d일 HH:mm` for 1-week, with no extra prefix or timezone suffix. A live 14sp countdown sits below each reset time; windows under a day use hours/minutes, while longer windows use `일+시간` (for example, `1일+2시간`). Solid gauge color uses clear bands: red (0–20%), amber (21–50%), teal (51–75%), and blue (76–100%).
- `StatusLine`: compact health indicator for bridge, app server, and activity.
- `CompletionStatusFlash`: a transition guard that reacts when Codex enters `completed`, keeps the current page selected, and drives the shared-header completion acknowledgement. The same event still requests a brief screen wake and uses the existing notification sound; the scheduled 5-hour reset remains an explicit Codex-page reveal.
- `ApprovalPrompt`: a Codex approval modal shown above either phone page when the Mac app server has a pending command, file-change, permission, or confirmation request. Its waiting motion, request title/detail, and explicit `승인`/`거절` actions remain visible until the response is accepted by the bridge; the same request remains available as an inline Codex card underneath.
- `BridgeConnectionSettingsDialog`: a compact selector opened from the header settings icon. It offers a 10-minute-step post-screen-off grace period (10분–12시간) or 계속 유지, a 1–10 second 완료 깜빡임 duration (2 seconds by default), plus an optional daily 절전 시간대 (start/end) in which screen-off pauses immediately and screen-on resumes the bridge.

## Accessibility and motion

- Preserve high-contrast white/gray text on black surfaces.
- Status motion is limited to the Codex activity indicators; usage gauges remain stable and communicate state through value, label, and color together.
- Codex activity motion: `RUNNING` uses a repeating progress sweep and pulse, `WAITING FOR APPROVAL` uses a slow breathing ring, `COMPLETED` uses a one-shot check draw-in with a brief halo, `FAILED` uses a short warning shake/pulse, and `IDLE` remains still.
- Running visibility: while `activeSessionCount > 0`, `RunningStatusIndicator` continuously rotates and pulses beside the `Codex 작업중` label in the always-mounted header; it is removed immediately when the active count reaches zero. A running-state reveal never forces the user away from Buttons; completion stays on the current page and flashes its independent header status, while approval or an explicit Codex reveal changes the selected tab.
- Idle blackout: when enabled in settings, the app keeps the display awake while foregrounded, shows the black overlay after the inactivity timeout, and reveals the underlying page on touch or a remote event without changing the page layout.
- Completion acknowledgement: when a new `completed` event arrives, the current page remains selected and the independent `Codex 작업 완료` header status blinks briefly in a high-contrast green treatment for the configured duration. Any touch, including a swipe, button press, page selection, or incidental tap, immediately stops the blink without affecting an active `Codex 작업중` status. If the display is off, the existing short wake window and notification sound still make the acknowledgement observable.
- Approval routing: when a new approval/confirmation request arrives while Buttons is visible, the app reveals Codex, wakes the display when needed, and shows a breathing approval motion with `승인` and `거절` actions. The selected decision is returned to the originating App Server request.
- Primary page navigation: the app has two pages, Buttons and Codex. A horizontal swipe can start anywhere in the full app surface, commits after a short 32dp movement, and advances to the next page with a 150ms directional slide/100ms fade. Repeated swipes in one direction wrap continuously. The bottom navigation is intentionally omitted so the 4×4 Buttons grid can use the full area below the header.
- Reset wake: the 5-hour `resetsAt` timestamp is sent as Unix epoch seconds and scheduled as an `RTC_WAKEUP` alarm with a direct `MainActivity` PendingIntent. The activity receives the Codex reveal intent, allowing the screen to wake at the reset boundary without depending on a foreground app page.
- Screen-off connection policy: the foreground bridge service keeps the socket and discovery locks only for the selected 10-minute-step grace period, then pauses the client while retaining the service. During the optional daily 절전 시간대, screen-off pauses immediately; a screen-on event resumes discovery immediately. The low-priority ongoing service notification explains whether the bridge is active or paused.
