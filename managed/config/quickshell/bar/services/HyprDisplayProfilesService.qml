pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  readonly property string profilesDir: Quickshell.env("HOME") + "/.config/hypr/hyprland/profiles"
  readonly property string metaPath: profilesDir + "/profiles.json"

  property var profiles: ({})
  property string activeProfileId: ""
  property string lastError: ""

  signal changed()

  function load() {
    loadProc.running = true;
  }

  function save() {
    const json = JSON.stringify({
      profiles: root.profiles || {},
      activeProfileId: root.activeProfileId || ""
    }, null, 2).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\$/g, "\\$").replace(/`/g, "\\`");
    saveProc.command = ["sh", "-lc", "mkdir -p \"$HOME/.config/hypr/hyprland/profiles\" && printf \"%s\" \"" + json + "\" > \"$HOME/.config/hypr/hyprland/profiles/profiles.json\""];
    saveProc.running = true;
  }

  function createProfile(name, outputsText) {
    const id = "profile_" + Date.now();
    const file = root.profilesDir + "/" + id + ".conf";
    writeProfileProc.command = ["sh", "-lc", "mkdir -p \"$HOME/.config/hypr/hyprland/profiles\" && cat > \"" + file + "\" <<'EOF'\n" + outputsText + "\nEOF"];
    writeProfileProc.running = true;
    const now = Date.now();
    const next = JSON.parse(JSON.stringify(root.profiles));
    next[id] = { id: id, name: name, file: file, createdAt: now, updatedAt: now };
    root.profiles = next;
    root.activeProfileId = id;
    save();
    changed();
  }

  function deleteProfile(id) {
    const p = root.profiles[id];
    if (p && p.file)
      deleteProfileProc.command = ["rm", "-f", p.file];
    deleteProfileProc.running = true;
    const next = JSON.parse(JSON.stringify(root.profiles));
    delete next[id];
    root.profiles = next;
    if (root.activeProfileId === id)
      root.activeProfileId = "";
    save();
    changed();
  }

  function activateProfile(id) {
    const p = root.profiles[id];
    if (!p || !p.file)
      return false;
    activateProc.command = ["sh", "-lc", "cp -f \"" + p.file + "\" \"$HOME/.config/hypr/hyprland/monitors.conf\" && hyprctl reload"];
    activateProc.running = true;
    root.activeProfileId = id;
    save();
    changed();
    return true;
  }

  Component.onCompleted: load()

  Process {
    id: loadProc
    running: false
    command: ["sh", "-lc", "mkdir -p \"$HOME/.config/hypr/hyprland/profiles\" && [ -f \"$HOME/.config/hypr/hyprland/profiles/profiles.json\" ] && cat \"$HOME/.config/hypr/hyprland/profiles/profiles.json\" || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const t = (text || "").trim();
        if (!t) {
          root.profiles = ({});
          root.activeProfileId = "";
          root.changed();
          return;
        }
        try {
          const parsed = JSON.parse(t);
          root.profiles = parsed.profiles || ({});
          root.activeProfileId = parsed.activeProfileId || "";
          root.changed();
        } catch (e) {
          root.lastError = "Invalid profiles metadata";
        }
      }
    }
  }

  Process { id: saveProc; running: false; command: [] }
  Process { id: writeProfileProc; running: false; command: [] }
  Process { id: deleteProfileProc; running: false; command: [] }
  Process { id: activateProc; running: false; command: [] }
}
