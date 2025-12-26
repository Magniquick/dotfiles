# QuickShell idle CPU investigation (2025-12-25)

## What was burning CPU

Idle QuickShell was sitting around ~`5%` CPU even when the powermenu was not visible.

Root cause was an always-running animation in the powermenu:

- `powermenu/FooterStatus.qml` had a `SequentialAnimation on opacity` with `running: true` (infinite blinking cursor).
- Even when the powermenu overlay was hidden (`visible: false`), that animation kept ticking every frame, which kept the scene graph active and burned CPU.

## Fix that dropped idle CPU

Change: gate the cursor blink animation to only run while the powermenu window is actually visible.

- File: `powermenu/FooterStatus.qml`
- Change: `running: true` → `running: footer.QsWindow.window && footer.QsWindow.window.visible`
- Also added `import Quickshell` so `QsWindow` is available.

After this change, with the powermenu loaded but hidden, idle CPU drops to ~`0.00%` (via `pidstat -p`).

## How to reproduce / measure

QuickShell CPU spikes right after QML reloads; wait ~20s before measuring.

### Quick one-shot (your original command)

This sometimes prints nothing if the value is zero on that sample:

```sh
sleep 20; pidstat -C quickshell 1 1 | awk 'END{print $8}'
```

### More reliable (pin to PID)

```sh
pid=$(pgrep -n quickshell)
sleep 20
pidstat -p "$pid" 1 5 | awk '/Average:/{print $8}'
```

## How it was isolated (disable/enable only)

I added an IPC target `profile` in `shell.qml` so components can be disabled without editing files repeatedly:

```sh
quickshell ipc show
quickshell ipc call profile preset all
quickshell ipc call profile setBarEnabled false
quickshell ipc call profile setPowermenuEnabled false
quickshell ipc call profile setHyprquickshotEnabled false
```

The key observation was:

- Disabling the bar did **not** remove the ~`5%` CPU.
- Disabling the powermenu did remove it.
- Hyprquickshot was not the contributor while idle/inactive.

## Notes

- I briefly tried `perf`, but stuck to the requested “disable components” method and fixed the animation once identified.
- Any sysctl changes (e.g. `kernel.perf_event_paranoid`) were temporary and restored.

