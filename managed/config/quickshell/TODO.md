# TODO

- [ ] Fix `DisplayConfigWindow` drag/position behavior in brightness popup
  Description: `bar/components/displayconfig/DisplayConfigWindow.qml` uses a `PopupWindow` with custom drag state (`popupX/popupY`) and anchor overrides. Current behavior is flaky ("can’t drag"/position jitter) and has already triggered layout/anchor warnings. Rework this to a stable draggable surface (either a proper movable `PanelWindow`/`FloatingWindow` style container or a popup with explicit non-layout drag handle + clamped coordinates), then verify no binding/layout warnings and reliable drag on multi-monitor setups.
