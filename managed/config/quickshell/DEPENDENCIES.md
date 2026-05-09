# Dependencies

Practical audit for this Quickshell config. Package names are Arch/CachyOS names
where they are obvious from command/module names.

## System Runtime

- `quickshell`: shell runtime; this config assumes the local binary tracks
  Quickshell master.
- Qt/QML runtime modules used directly: `qt6-declarative`, `qt6-5compat`,
  `syntax-highlighting` for `org.kde.syntaxhighlighting`, plus the Qt modules
  pulled by Quickshell services (`Hyprland`, `Wayland`, `Pipewire`, `UPower`,
  `Mpris`, `SystemTray`, `Notifications`, `Pam`, `Bluetooth`, `Networking`).
- Hyprland session tools: `hyprctl` (`hyprland`) for overview/workspace/DPMS
  paths.
- Notifications: `notify-send` (`libnotify`) for dependency warnings and
  HyprQuickshot status notifications.
- System/D-Bus helpers: `systemctl`, `systemd-inhibit`, `busctl`
  (`systemd`), and debug-only `dbus-monitor` (`dbus`).
- Basic process/network helpers: `ip` (`iproute2`), `ps` (`procps-ng`),
  `fuser` (`psmisc`), `inotifywait` (`inotify-tools`).

## Feature Runtime Commands

- Backlight: `ddcutil` for external monitor DDC/CI. Internal brightness goes
  through `qsgo.BacklightProvider`.
- Updates: `checkupdates` (`pacman-contrib`) and `yay -Qua` (`yay`) via
  `qsgo.PacmanUpdatesProvider`; update sync
  shells to `sudo pacman -Sy`.
- Battery charge policy: `hp-charge-control` for HP charge limit/auto/resume
  controls. This is local/AUR-style tooling, not a generic system package.
- Privacy: `inotifywait`, `fuser`, `ps` for camera owners; `wl-present` for
  click-to-freeze. `wl-present` appears to be a local/materialized helper.
- Bluetooth diagnostics: debug-only `dbus-monitor`, `busctl`, `ps`; librepods
  tray metadata is read through StatusNotifierItem D-Bus when debug is enabled.
- HyprQuickshot recording/copy: `wl-screenrec`, `wl-copy` (`wl-clipboard`),
  `pactl` (`libpulse`). Screenshot capture itself is native `qscapture`.
- HyprQuickshot notification actions/OCR: `gdbus` (`glib2`), `xdg-open`
  (`xdg-utils`), optional `tesseract` and `zbarimg`.
- Lockscreen wallpaper query: `awww query`; package/source is ambiguous in-tree.
- AI/calendar/Todoist/email: Secret Service provider plus secrets under service
  `quickshell`. Common setup is `gnome-keyring` + `libsecret`/`secret-tool`.
- Disk health in `qsgo.SysInfoProvider`: optional `smartctl`
  (`smartmontools`); missing state displays as unknown.

## Native Module Build Deps

Common:

- `base-devel`, `cmake`, `ninja`, `pkgconf`.
- Qt 6 development packages for `Core`, `Gui`, `Qml`, `Network`, `Concurrent`
  and `qmlplugindump` (`qt6-base`, `qt6-declarative`).
- `go`; current `go.mod` files declare Go `1.25.x`.

Per module:

- `common/modules/qs-go`: Go + CGO + Qt6 Core/Gui/Qml/Network. Build with
  `./tools/build-qs-go.sh`.
- `common/modules/qs-capture`: Qt6 Core/Gui/Qml/Concurrent, `pixman`,
  `libpng`, `wayland`, `wayland-protocols`, `wayland-scanner`. Build with
  `bash tools/build-qs-capture.sh`.
- `common/modules/qsmath`: Qt6 Core/Gui/Qml/Concurrent plus Cargo for the
  small bundled RaTeX SVG helper. Build with `bash tools/build-qsmath.sh`.
- `common/modules/unified-lyrics-api`: Go + CGO + Qt6 Core/Qml/Concurrent.
  Build with CMake from that module directory.

## Math / LaTeX Renderer

- Current left-panel math rendering imports `qsmath 1.0`; the plugin keeps that
  QML API and shells out to the bundled `qsmath-render-svg` helper built from
  `common/modules/qsmath/ratex-helper`.
- The helper uses RaTeX crates directly, so inline math can render with zero
  SVG padding while display math keeps explicit margins from the QML call.
- Runtime lookup prefers the bundled build output, then `qsmath-render-svg` in
  `PATH`, then the older external RaTeX `render-svg` fallback.
- The SVG cache key includes the renderer binary path, size, and mtime, so
  helper updates naturally miss old cached SVGs.
- `tools/render-latex.sh` remains a small wrapper around the external RaTeX
  `render-svg` CLI for manual one-off rendering.

## Optional / Materialized Local Tools

- `hp-charge-control`: HP battery policy helper used by `BatteryModule`.
- `wl-present`: privacy freeze toggle helper used by `PrivacyService`.
- `awww`: lockscreen wallpaper query helper; source/package not established
  by this tree.
- RaTeX `render-svg`: installed by Cargo into the user Cargo bin, not vendored
  into this repo.
- Vendored/local assets: `common/materialkit` and
  `common/modules/rounded_polygon_qmljs` are in-tree, not package-manager deps.

## HyprChat Reference

`archived/hyprchat/` is reference/upstream material, not the active left-panel backend.
Its own package template lists:

- Runtime: `quickshell`, `gnome-keyring`, `libsecret`, `openssl`,
  `inotify-tools`, `kitty`.
- Build: `dotnet-sdk>=10`.
- Optional: `github-cli` for GitHub Copilot device flow login.
