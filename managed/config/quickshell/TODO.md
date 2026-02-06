# Code Simplification TODO

## Next (Performance + Maintainability)

- [ ] HyprQuickshot: Extract `processScreenshot()` logic out of QML
  Description: `hyprquickshot/shell.qml` still contains a large JS-heavy `processScreenshot(x, y, w, h)` function (path resolution, scaling, timestamp formatting, orchestration). Move pure logic to a dedicated `.js` helper (or `qs-native`) and keep QML focused on state + UI.

- [ ] HyprQuickshot: Remove `Canvas` icon paint code
  Description: `hyprquickshot/ui/ControlBar.qml` uses `Canvas.onPaint` to draw the freeze/play icon. Replace with static SVG assets (or a font glyph) and switch `Image.source` based on `screenFrozen` to reduce JS work and improve maintainability.

- [ ] Network: Extract parsers out of `NetworkService.qml`
  Description: `bar/services/NetworkService.qml` mixes process control with extensive string parsing/state mutation. Pull parsing helpers into `bar/services/network/*.js` (or a native module) and keep the service as “state + timers + process IO”.

- [x] Fix singleton service root objects that host child QML objects
  Description: Some `bar/services/*.qml` singletons were `QtObject {}` with `Timer`/`Connections`/provider children, which triggers `Cannot assign to non-existent default property` at load time. Converted them to `Item { visible: false }`.

- [x] Finish HyprQuickshot UI decomposition wiring
  Description: `hyprquickshot/shell.qml` now uses `hyprquickshot/ui/ControlBar.qml` and `hyprquickshot/ui/CountdownOverlay.qml`, with pulse calls routed through `countdownOverlay.pulse()`.

- [x] Validate `quickshell` loads with `QML_IMPORT_PATH` set
  Description: Verified `QML_IMPORT_PATH=~/.config/quickshell/common/modules/qs-native/build/qml quickshell` reaches “Configuration Loaded”.

- [x] Hoist per-screen monitors into shared services (multi-monitor perf)
  Description: `shell.qml` creates a `bar/BarWindow.qml` per screen; modules spawn subprocess monitors/timers. Done for systemd failures (`bar/services/SystemdFailedService.qml`), updates (`bar/services/UpdatesService.qml`), Todoist (`bar/services/TodoistService.qml`), calendar (`bar/services/CalendarService.qml`), backlight (`bar/services/BacklightService.qml`), and network (`bar/services/NetworkService.qml`).

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
