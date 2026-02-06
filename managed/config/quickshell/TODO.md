# Code Simplification TODO

## Next (Performance + Maintainability)

- [ ] Hoist per-screen monitors into shared services (multi-monitor perf)
  Description: `shell.qml` creates a `bar/BarWindow.qml` per screen; modules spawn subprocess monitors/timers. Done for systemd failures via `bar/services/SystemdFailedService.qml`; remaining high-impact candidates: `NetworkModule`, `BacklightModule`, `UpdatesModule`, `ToDoModule`, calendar refresh.

- [x] Remove API keys from process argv in LeftPanel AI client
  Description: `leftpanel/LeftPanel.qml` currently builds `curl` commands with secrets in the URL/header, which are visible via process listings. Refactor to pass secrets via `Process.environment` and send request bodies using `stdinEnabled + write()` (or move the client into `common/modules/qs-native`).

- [ ] Split `leftpanel/LeftPanel.qml` into view + controller + model
  Description: `leftpanel/LeftPanel.qml` mixes config IO, chat state, command parsing, network IO, and rendering. Introduce `leftpanel/services/AiClient.qml` and a small `ChatStore` object (prefer `ListModel` for messages) so the view stays declarative and smaller.

- [x] Fix `bar/components/CommandRunner.qml` double-trigger on startup
  Description: `Component.onCompleted: trigger()` plus timer immediate-trigger logic causes two initial executions. Keep a single trigger mechanism (use `Timer.triggeredOnStart: true`).

- [x] Coalesce bursty `on*Changed` recomputations (reduce binding churn)
  Description: Examples include `bar/modules/UpdatesModule.qml` calling `updateFromProvider()` on multiple provider changes, and `bar/components/TooltipPopup.qml` recomputing anchors on every geometry change. Add a small coalescer (`Qt.callLater`) helper and use it to batch updates.

- [x] Convert notification store arrays to a real model
  Description: `rightpanel/RightPanel.qml` uses `property var list/popupList` with array copies and `filter()` rebuilds. Replace with `ListModel` plus `append/insert/remove` and track popup state incrementally to avoid O(n) allocation churn.

- [ ] Gate or remove always-running animations
  Description: Audit for infinite `loops: Animation.Infinite` animations and ensure they only run while visible/needed.

- [ ] Reduce `Qt5Compat.GraphicalEffects` usage in scrolling lists
  Description: `OpacityMask` can be FBO-heavy under `ListView` and in always-instantiated tooltip content. Gated masks in `rightpanel/components/NotificationContent.qml` and `bar/modules/MprisModule.qml`; consider further reducing usage or lazy-loading tooltip content.

- [ ] Make `screen:` explicit for all Wayland windows/popups
  Description: Bind windows to the intended output to avoid “default monitor” surprises on multi-monitor setups. Done for `rightpanel/RightPanel.qml` popups; left/right panels in `shell.qml` still need an explicit screen selection strategy.

- [ ] Revisit bar layer configuration
  Description: `bar/BarWindow.qml` sets `WlrLayershell.layer: WlrLayer.Background`, which can put the bar behind clients depending on compositor behavior. Consider `Top` (or `Overlay`) and verify expected focus/exclusive zone behavior.

- [x] Remove `Config.devicePixelRatio` derived from `screens[0]`
  Description: Mixed-DPI setups will render tray icons incorrectly when using the first screen's DPR. Prefer per-window `Screen.devicePixelRatio` (or derive DPR from the owning window's `screen`).

- [ ] Reduce `["sh","-c", ...]` usage and centralize it when unavoidable
  Description: Many modules execute shell strings via `Quickshell.execDetached(["sh","-c", ...])`. Prefer argument arrays for fixed commands, and route configurable commands through a single helper that handles quoting and validation.

## Completed

- [x] Duplicated Exponential Backoff Pattern (Refactored to `ProcessMonitor.qml`)
- [x] Repeated Tooltip Header Pattern (Refactored to `TooltipHeader.qml`)
- [x] Repeated Section Header Pattern (Refactored to `SectionHeader.qml`)
- [x] loginShell Duplication (Moved to `Config.qml`)
- [x] Percentage Normalization (Added `normalizePercent` to `BatteryModule`)
- [x] Hardcoded Font Family in `PowermenuButton` (Fixed)
- [x] Hardcoded Animation Durations in `PowermenuButton` (Fixed)
- [x] Verify Deleted Files (Verified)
