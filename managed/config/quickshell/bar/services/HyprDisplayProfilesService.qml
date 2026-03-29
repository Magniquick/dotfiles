pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  readonly property string profilesDir: Quickshell.env("HOME") + "/.config/hypr/hyprland/monitor-profiles"
  readonly property string metaPath: profilesDir + "/profiles.json"
  readonly property string legacyProfilesDir: Quickshell.env("HOME") + "/.config/hypr/hyprland/profiles"
  readonly property string legacyMetaPath: legacyProfilesDir + "/profiles.json"

  property var profiles: ({})
  property string activeProfileId: ""
  property string lastError: ""

  signal changed()

  function slugifyName(name) {
    const base = String(name || "")
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
    return base || "profile";
  }

  function load() {
    let t = (metaFile.text() || "").trim();
    if (!t)
      t = (legacyMetaFile.text() || "").trim();
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

  function save() {
    const json = JSON.stringify({
      profiles: root.profiles || {},
      activeProfileId: root.activeProfileId || ""
    }, null, 2) + "\n";
    writeMetaProc.command = ["sh", "-lc", "mkdir -p \"$HOME/.config/hypr/hyprland/monitor-profiles\" && cat > \"" + root.metaPath + "\" <<'EOF'\n" + json + "EOF"];
    writeMetaProc.running = true;
  }

  function createProfile(name, outputsText) {
    const slug = root.slugifyName(name);
    const id = slug + "-" + Date.now();
    const file = root.profilesDir + "/" + id + ".conf";
    writeProfileProc.command = ["sh", "-lc", "mkdir -p \"$HOME/.config/hypr/hyprland/monitor-profiles\" && cat > \"" + file + "\" <<'EOF'\n" + outputsText + "\nEOF"];
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

  FileView {
    id: metaFile
    path: root.metaPath
    blockLoading: true
    blockWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  FileView {
    id: legacyMetaFile
    path: root.legacyMetaPath
    blockLoading: true
    blockWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  Process { id: writeProfileProc; running: false; command: [] }
  Process { id: writeMetaProc; running: false; command: [] }
  Process { id: deleteProfileProc; running: false; command: [] }
  Process { id: activateProc; running: false; command: [] }
}
