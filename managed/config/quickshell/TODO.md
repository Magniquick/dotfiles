# TODO

- [ ] Fix `DisplayConfigWindow` drag/position behavior in brightness popup
  Description: `bar/components/displayconfig/DisplayConfigWindow.qml` uses a `PopupWindow` with custom drag state (`popupX/popupY`) and anchor overrides. Current behavior is flaky ("can’t drag"/position jitter) and has already triggered layout/anchor warnings. Rework this to a stable draggable surface (either a proper movable `PanelWindow`/`FloatingWindow` style container or a popup with explicit non-layout drag handle + clamped coordinates), then verify no binding/layout warnings and reliable drag on multi-monitor setups.

## Command Replacement Roadmap

- [x] 1. Replace notification image file existence subprocess in `rightpanel/components/NotificationContent.qml`
  Description: Remove the `test -f` process check and switch to an in-process approach such as `FileView` or image loading status.

- [x] 2. Replace URL opening subprocess in `bar/components/TooltipPopup.qml`
  Description: Stop using `xdg-open` for URL strings and use `Qt.openUrlExternally()` instead.

- [x] 3. Remove Bluetooth connect/disconnect fallback subprocesses in `bar/modules/BluetoothModule.qml`
  Description: Replace `bluetoothctl connect/disconnect` fallback calls with native `Quickshell.Bluetooth` device actions.

- [x] 4. Remove Bluetooth scan state probe subprocess in `bar/modules/BluetoothModule.qml`
  Description: Replace `bluetoothctl show` scanning-state probes with native adapter state from `Quickshell.Bluetooth`.

- [x] 5. Remove Bluetooth scan toggle subprocess in `bar/modules/BluetoothModule.qml`
  Description: Replace `bluetoothctl scan on/off` dispatch with native adapter discovery control where possible.

- [x] 6. Replace Hyprland monitor query subprocess in `bar/services/HyprDisplayService.qml`
  Description: Replace `hyprctl -j monitors all` with `Quickshell.Hyprland` monitor data and refresh flows.

- [x] 7. Replace Hyprland debug query subprocesses in `hyprdebug/shell.qml`
  Description: Replace `hyprctl clients`, `activeworkspace`, and `activewindow` debug dumps with native Hyprland models where available.

- [x] 8. Replace Hyprland DPMS subprocess in `common/services/IdleManager.qml`
  Description: Replace `hyprctl dispatch dpms on/off` with native Hyprland dispatch support if the API behaves equivalently.

- [x] 9. Replace Hyprland exit subprocess in `lockscreen/LockSurface.qml`
  Description: Replace `hyprctl dispatch exit` with native Hyprland dispatch support.

- [x] 10. Reduce network detail subprocesses in `bar/services/NetworkService.qml`
  Description: Use `Quickshell.Networking` for all state it exposes and keep CLI usage only for metadata still missing from the API.

- [x] 11. Replace display profile metadata shell IO in `bar/services/HyprDisplayProfilesService.qml`
  Description: Move JSON profile reads and writes off shell pipelines and onto in-process file handling.

- [x] 12. Replace display config shell IO in `bar/services/HyprDisplayService.qml`
  Description: Move `monitors.conf` reads and writes off shell pipelines and onto in-process file handling where practical.

- [x] 13. Re-evaluate notification daemon status subprocess in `rightpanel/RightPanel.qml`
  Description: Determine whether `busctl --user status org.freedesktop.Notifications` can be removed or replaced by in-process state management.

- [x] 14. Replace separate powermenu shell spawn with in-process presentation
  Description: Stop spawning a separate `quickshell --path ...` instance for powermenu entry points and host the UI in-process.

- [x] 15. Reduce camera privacy subprocesses in `bar/services/PrivacyService.qml`
  Description: Keep native `Pipewire` privacy tracking where possible and revisit whether any of the camera-specific probes can be removed or localized.

- [x] 16. Rework systemd failed-unit tracking in `bar/services/SystemdFailedService.qml`
  Description: Investigate whether the current `systemctl` and `dbus-monitor` approach can be narrowed, replaced, or moved into a more native integration path.

- [x] 17. Revisit external monitor brightness subprocesses in `bar/services/BrightnessService.qml`
  Description: Confirm whether `ddcutil` remains necessary for DDC/CI displays and document any unavoidable external dependency.

- [x] 18. Revisit HyprQuickshot recording and notification subprocesses in `hyprquickshot/`
  Description: Audit `wl-screenrec`, `pactl`, `notify-send`, `wl-copy`, temp-file management, and related helper script usage to remove only what Quickshell can actually replace.
