# Code Simplification TODO

## Next (Performance + Maintainability)

- [x] Fix `CommandRunner` to only publish stdout on success
  Description: `bar/components/CommandRunner.qml:72-102` currently sets `root.output` in `stdout.onStreamFinished` even if the command later exits non-zero, so downstream `onOutputChanged` handlers can consume partial/invalid output. Change to buffer stdout internally and only assign `root.output`/emit `ran()` when `onExited` sees `code === 0` (and optionally when `stderr` is empty). Also decide whether `output` should be cleared on failure vs left untouched. (Implemented: stdout buffered; `output` cleared at trigger; `ran()` only emitted on success.)

- [x] Fix `PrivacyService` false negatives from early `return false`
  Description: `bar/services/PrivacyService.qml:24-45` returns `false` immediately when encountering a muted input stream, which can mask other active streams. Similar pattern exists in `bar/services/PrivacyService.qml:103-135` for screensharing. Replace "muted => return false" with "muted => continue" and only return false after scanning all nodes.

- [x] Make updates polling/sync sane; add timeouts + coalescing in `PacmanUpdatesProvider`
  Description: `bar/services/UpdatesService.qml:62-69` calls `provider.sync()` every 5 minutes, and `common/modules/qs-native/src/lib.rs:519-525` runs `checkupdates` without `--nosync` (DB sync). Reduce churn by removing frequent background sync (make manual or daily), increase refresh interval, and ensure AUR RPC has a timeout (`common/modules/qs-native/src/lib.rs:357-372` currently uses `reqwest::blocking::get` without a timeout). Add an in-flight guard so repeated `refresh()` calls coalesce instead of spawning unbounded threads (`common/modules/qs-native/src/lib.rs:469-516`). (Implemented: refresh 30s, sync daily/no startup; AUR reqwest client timeouts; refresh in-flight coalescing.)

- [x] Make chat history operations stable (IDs, not body text matching)
  Description: `leftpanel/stores/ChatStore.qml:32-56` uses body-string matching to locate history entries, and `leftpanel/controllers/ChatController.qml:123-130` truncates history based on user body strings. This breaks when messages repeat. Introduce stable message IDs and store them in both the `ListModel` and the `history` array; operate on IDs for delete/edit/regenerate. (Implemented: `messageId` role in model + history; delete/edit/truncate keyed on IDs; request payload derived from history.)

- [x] Stop right panel from thrashing `NotificationServer` via frequent `busctl` polling
  Description: `rightpanel/RightPanel.qml:233-255` spawns `busctl` every 10s and toggles the `NotificationServer` loader off/on on failure (`:252-254`), which can create a permanent respawn loop if `busctl` is missing or the service is transient. Prefer a long-lived server and either remove polling or add exponential backoff + a failure budget before recreating. (Implemented: loader no longer toggled; status polling uses exponential backoff up to 5m.)

- [x] Clarify `TooltipPopup.browserLink` intent and execute safely
  Description: `bar/components/TooltipPopup.qml:249-254` calls `ProcessHelper.execDetached(browserLink)`; this fails if `browserLink` is a URL and invites shell injection if treated as a command. Decide: if it's a URL, run `xdg-open` with argv; if it's a command, rename it (e.g. `browserCommand`) and keep shell execution explicit. (Implemented: string = URL opened via `xdg-open`; argv array executes detached; shell strings refused.)

- [x] HyprQuickshot: remove duplicate `Ui` import alias
  Description: `hyprquickshot/shell.qml:13-18` imports `"ui"` as `Ui` twice (and again as `"./ui" as Ui`). Keep a single `Ui` import to avoid confusion/tooling/runtime issues.

- [x] HyprQuickshot: remove/fix dead overlay Rectangle
  Description: `hyprquickshot/src/FreezeScreen.qml:124-130` has a `Rectangle` with `opacity` always 0, making it a no-op but still in the object tree. Either delete it or set the intended opacity/behavior. (Implemented: made it an invisible input shield while the transparent surface grab is active.)

- [x] HyprQuickshot: Extract `processScreenshot()` logic out of QML
  Description: `hyprquickshot/shell.qml` still contains a large JS-heavy `processScreenshot(x, y, w, h)` function (path resolution, scaling, timestamp formatting, orchestration). Move pure logic to a dedicated `.js` helper (or `qs-native`) and keep QML focused on state + UI.

- [x] HyprQuickshot: Remove `Canvas` icon paint code
  Description: `hyprquickshot/ui/ControlBar.qml` uses `Canvas.onPaint` to draw the freeze/play icon. Replace with static SVG assets (or a font glyph) and switch `Image.source` based on `screenFrozen` to reduce JS work and improve maintainability.

- [x] Network: Extract parsers out of `NetworkService.qml`
  Description: `bar/services/NetworkService.qml` mixes process control with extensive string parsing/state mutation. Pull parsing helpers into `bar/services/network/*.js` (or a native module) and keep the service as “state + timers + process IO”.

- [x] Fix singleton service root objects that host child QML objects
  Description: Some `bar/services/*.qml` singletons were `QtObject {}` with `Timer`/`Connections`/provider children, which triggers `Cannot assign to non-existent default property` at load time. Converted them to `Item { visible: false }`.

- [x] Finish HyprQuickshot UI decomposition wiring
  Description: `hyprquickshot/shell.qml` now uses `hyprquickshot/ui/ControlBar.qml` and `hyprquickshot/ui/CountdownOverlay.qml`, with pulse calls routed through `countdownOverlay.pulse()`.

- [x] Validate `quickshell` loads with `QML_IMPORT_PATH` set
  Description: Verified `QML_IMPORT_PATH=~/.config/quickshell/common/modules/qs-native/build/qml quickshell` reaches “Configuration Loaded”.

- [x] Hoist per-screen monitors into shared services (multi-monitor perf)
  Description: `shell.qml` creates a `bar/BarWindow.qml` per screen; modules spawn subprocess monitors/timers. Done for systemd failures (`bar/services/SystemdFailedService.qml`), updates (`bar/services/UpdatesService.qml`), Todoist (`bar/services/TodoistService.qml`), calendar (`bar/services/CalendarService.qml`), brightness (`bar/services/BrightnessService.qml` + `qsnative.BacklightProvider`), and network (`bar/services/NetworkService.qml`).

- [x] Remove API keys from process argv in LeftPanel AI client
  Description: `leftpanel/LeftPanel.qml` currently builds `curl` commands with secrets in the URL/header, which are visible via process listings. Refactor to pass secrets via `Process.environment` and send request bodies using `stdinEnabled + write()` (or move the client into `common/modules/qs-native`).

- [x] Split `leftpanel/LeftPanel.qml` into view + controller + model
  Description: Introduced `leftpanel/stores/ChatStore.qml`, `leftpanel/controllers/ChatController.qml`, and `leftpanel/views/LeftPanelView.qml`; `leftpanel/LeftPanel.qml` is now a composition root. Env/config parsing moved into `leftpanel/services/EnvLoader.qml` and `leftpanel/services/MoodConfig.qml`.

- [x] Fix `bar/components/CommandRunner.qml` double-trigger on startup
  Description: `Component.onCompleted: trigger()` plus timer immediate-trigger logic causes two initial executions. Keep a single trigger mechanism (use `Timer.triggeredOnStart: true`).

- [x] Coalesce bursty `on*Changed` recomputations (reduce binding churn)
  Description: Examples include `bar/modules/UpdatesModule.qml` calling `updateFromProvider()` on multiple provider changes, and `bar/components/TooltipPopup.qml` recomputing anchors on every geometry change. Add a small coalescer (`Qt.callLater`) helper and use it to batch updates.

- [x] Convert notification store arrays to a real model
  Description: `rightpanel/RightPanel.qml` uses `property var list/popupList` with array copies and `filter()` rebuilds. Replace with `ListModel` plus `append/insert/remove` and track popup state incrementally to avoid O(n) allocation churn.

- [x] Gate or remove always-running animations
  Description: Gated all `Animation.Infinite` usages found behind window visibility checks.

- [x] Reduce `Qt5Compat.GraphicalEffects` usage in scrolling lists
  Description: `OpacityMask` is now lazy-instantiated via `Loader` with viewport gating (notifications) and tooltip gating (MPRIS), and uses `cached: true`.

- [x] Make `screen:` explicit for all Wayland windows/popups
  Description: Bind windows to the intended output to avoid “default monitor” surprises on multi-monitor setups. `shell.qml` now binds left/right panels to the screen that triggered them (falling back to `screens[0]`). `rightpanel/RightPanel.qml` popups also bind to the owning panel screen.

- [x] Revisit bar layer configuration
  Description: `bar/BarWindow.qml` now uses `WlrLayershell.layer: WlrLayer.Top` and explicitly disables keyboard focus to avoid focus stealing.

- [x] Remove `Config.devicePixelRatio` derived from `screens[0]`
  Description: Mixed-DPI setups will render tray icons incorrectly when using the first screen's DPR. Prefer per-window `Screen.devicePixelRatio` (or derive DPR from the owning window's `screen`).

- [x] Reduce `["sh","-c", ...]` usage and centralize it when unavoidable
  Description: Introduced `common/services/ProcessHelper.qml` and migrated shell-string execution sites to `ProcessHelper` (using argv arrays where practical).

## Completed

- [x] Duplicated Exponential Backoff Pattern (Refactored to `ProcessMonitor.qml`)
- [x] Repeated Tooltip Header Pattern (Refactored to `TooltipHeader.qml`)
- [x] Repeated Section Header Pattern (Refactored to `SectionHeader.qml`)
- [x] loginShell Duplication (Moved to `Config.qml`)
- [x] Percentage Normalization (Added `normalizePercent` to `BatteryModule`)
- [x] Hardcoded Font Family in `PowermenuButton` (Fixed)
- [x] Hardcoded Animation Durations in `PowermenuButton` (Fixed)
- [x] Verify Deleted Files (Verified)
